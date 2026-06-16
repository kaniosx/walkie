require "test_helper"

# Proves the single-Walker accept invariant under REAL thread contention — the
# PRD Guardrail's load-bearing race, settled at the model/DB layer before
# S-05's HTTP test exists. Minitest wraps each test in a transaction by
# default, which serializes thread writes and hides the race; this class opts
# out so the threads hit the real DB and contend on the one row.
class WalkConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  WALKER_COUNT = 10
  # Dedicated email domain for this class's rows. Purging by it makes setup
  # self-healing: a row leaked by an earlier run can't collide on uniqueness.
  EMAIL_DOMAIN = "walk-race.test"

  def setup
    purge_fixtures # clear any leftovers from a prior interrupted run first
    @owner = User.create!(email_address: "owner@#{EMAIL_DOMAIN}", password: "secret123",
                          password_confirmation: "secret123", role: "owner", city: "Kraków", postcode: "30-001")
    @dog = Dog.create!(name: "Rex", user: @owner)
    @walkers = WALKER_COUNT.times.map do |i|
      User.create!(email_address: "racer#{i}@#{EMAIL_DOMAIN}", password: "secret123",
                   password_confirmation: "secret123", role: "walker", city: "Kraków", postcode: "30-001")
    end
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków")
  end

  # No transactional rollback here — tear the rows down by hand.
  def teardown
    purge_fixtures
  end

  test "exactly one walker wins a simultaneous accept! race" do
    # All threads line up at the barrier and release together, so the accept!
    # calls genuinely overlap rather than running one-after-another.
    barrier = Concurrent::CyclicBarrier.new(WALKER_COUNT)
    results = Concurrent::Array.new

    threads = @walkers.map do |walker|
      Thread.new do
        barrier.wait
        # Own connection per thread (checked back in after the block) so the
        # threads contend on the row at the DB, not on a shared connection.
        ActiveRecord::Base.connection_pool.with_connection do
          walk = Walk.find(@walk.id)
          results << walk.accept!(walker)
        end
      end
    end
    threads.each(&:join)

    winners = results.count { |won| won }
    assert_equal 1, winners, "expected exactly one winning accept!, got #{winners}"

    @walk.reload
    assert @walk.accepted?, "walk should end in the accepted state"
    assert_not_nil @walk.accepted_by_walker_id, "winner must be recorded"
    assert_includes @walkers.map(&:id), @walk.accepted_by_walker_id
  end

  private
    # Delete every row tied to this class's users, by email domain rather than
    # by the @ivars — so it cleans up regardless of how far setup got. Order
    # respects the RESTRICT FKs: walks → dogs → users.
    def purge_fixtures
      user_ids = User.where("email_address LIKE ?", "%@#{EMAIL_DOMAIN}").pluck(:id)
      return if user_ids.empty?

      Walk.where(owner_id: user_ids).delete_all
      Dog.where(user_id: user_ids).delete_all
      User.where(id: user_ids).delete_all
    end
end

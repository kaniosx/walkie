require "test_helper"

# Proves the DB rejects inconsistent walk rows even when Active Record is
# bypassed — the PRD Guardrail is "binding outside the UI, not advisory".
# These go straight to SQL via the connection so no AR validation/callback runs;
# only the CHECK constraints stand between a bad write and the table.
class WalkConstraintsTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "c-owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner")
    @walker = User.create!(email_address: "c-walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker")
    @dog = Dog.create!(name: "Rex", user: @owner)
  end

  # Raw INSERT, no Active Record model in the path. accepted_by_walker_id is
  # passed literally ("NULL" or an id) so we exercise each constraint directly.
  def raw_insert_walk(state:, walker_sql: "NULL")
    sql = <<~SQL
      INSERT INTO walks (dog_id, owner_id, accepted_by_walker_id, state, city, created_at, updated_at)
      VALUES (#{@dog.id}, #{@owner.id}, #{walker_sql}, '#{state}', 'Kraków', NOW(), NOW())
    SQL
    ActiveRecord::Base.connection.execute(sql)
  end

  test "invalid state value is rejected" do
    assert_raises(ActiveRecord::StatementInvalid) do
      raw_insert_walk(state: "bogus")
    end
  end

  test "accepted row with NULL walker is rejected" do
    assert_raises(ActiveRecord::StatementInvalid) do
      raw_insert_walk(state: "accepted", walker_sql: "NULL")
    end
  end

  test "requested row with a non-null walker is rejected" do
    assert_raises(ActiveRecord::StatementInvalid) do
      raw_insert_walk(state: "requested", walker_sql: @walker.id.to_s)
    end
  end

  test "a valid requested row inserts" do
    # No Walk model yet (Phase 3) — count straight from the table.
    count = -> { ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM walks") }
    before = count.call
    raw_insert_walk(state: "requested", walker_sql: "NULL")
    assert_equal before + 1, count.call
  end
end

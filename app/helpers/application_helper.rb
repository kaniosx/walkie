module ApplicationHelper
  # Distance from the walk's (Owner's) coordinates to the assigned Walker's
  # last-cached location. nil whenever there's no assigned Walker yet or the
  # cache entry is absent/expired — callers render nothing in that case, no
  # placeholder/error state (see plan §What We're NOT Doing).
  def distance_to_walker_km(walk)
    return nil if walk.accepted_by_walker.nil?

    location = WalkerLocationCache.read(walk.accepted_by_walker)
    return nil if location.nil?

    walk.distance_km_to(location[:latitude], location[:longitude])
  end

  def walk_state_badge_classes(state)
    base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium "
    colour = case state.to_s
    when "requested"   then "bg-blue-100 text-blue-700"
    when "accepted"    then "bg-yellow-100 text-yellow-700"
    when "in_progress" then "bg-orange-100 text-orange-700"
    when "completed"   then "bg-green-100 text-green-700"
    when "cancelled"   then "bg-stone-100 text-stone-600"
    else                    "bg-stone-100 text-stone-500"
    end
    base + colour
  end
end

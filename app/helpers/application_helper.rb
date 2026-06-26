module ApplicationHelper
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

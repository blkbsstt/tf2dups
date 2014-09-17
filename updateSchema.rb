require "./tf2api"
class String
  def title
    str = "|| " + self + " ||"
    size = str.size
    stars = "*" * size
    stars + "\n" + str + "\n" + stars
  end
end
puts "Updating the Item Schema".title
Schema.update

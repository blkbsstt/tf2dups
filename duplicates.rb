require "./tf2api"
require "optparse"

options = {}
$stdout.sync = true

OptionParser.new do |opts|
  opts.banner = "Usage: ruby duplicates.rb --accounts=ACCOUNTS [options]"

  opts.on("-a", "--accounts ACCOUNTS", Array,
          "Specify a comma-separated list of accounts.") do |accounts|
    options[:accounts] = accounts
  end

  opts.on("-f", "--friends FRIENDS", Array,
          "Specify a comma-separated list of friends' accounts. " +
          "Will reserve items given friends need.") do |f|
    options[:friends] = f
  end

  opts.on("-l", "--list",
          "Display duplicate item lists.") do |l|
    options[:list] = l
  end

  opts.on("-s", "--scrap",
          "Calculate optimal scrap combinations.") do |s|
    options[:scrap] = s
  end

  opts.on("-v", "--log",
          "Turn on logging.") do |v|
    WebAPI.log = v
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

raise OptionParser::MissingArgument if options[:accounts].nil?

class String
  def title
    str = "|| " + self + " ||"
    size = str.size
    stars = "*" * size
    stars + "\n" + str + "\n" + stars
  end

  def underline(und = "=")
    self + "\n" + (und * self.strip.length)
  end
end

def prependLines(str, pre)
  str.split("\n").map{|s| pre + s}.join("\n")
end

puts "Finding Steam accounts".title
accounts = options[:accounts].map{|i| SteamID[i]}.compact

puts "\n" + "Getting items".title
weapons = accounts.map(&:items).inject(&:+).select(&:weapon?)

trade = Hash[
  weapons.duplicates.select{ |_, items| items.any?(&:will_trade?) }.map do |base_item, items|
    tradable = items.select(&:will_trade?)
    tradable.pop if tradable.size == items.size #save at least one!
    [base_item, tradable]
  end
]

if(options[:list])
  puts "\n" + "Duplicate Lists".title

  item_counts = Hash[trade.map{|base_item, items| [base_item, items.size]}]
  total_count = item_counts.values.inject(0,:+)

  puts("\nDuplicates by name [#{total_count}]".underline)

  space = item_counts.values.max * 3 + 1
  item_counts.sort_by{ |item, count| item.base_name }.each do |item, count| 
    puts "|_|" * count + " " * (space - count * 3) + "| #{item}"
  end

  puts("\nDuplicates by class [#{total_count}]".underline)

  byclass = item_counts.flat_map do |item, count|
    item.classes.map{ |klass| [klass, [item, count]] }
  end

  def grouped(arrays)
    Hash[arrays.group_by(&:first).map{|i,j| [i, j.flat_map{|k| k[1..-1]}]}]
  end

  TAB="    "

  SLOT = {"primary"   => "Primary",
          "secondary" => "Secondary",
          "melee"     => "Melee",
          "pda2"      => "Watch"}

  grouped(byclass).sort_by{ |klass, items| Schema.classRoleOrder.index(klass) }
                  .each do |klass,items|
      puts prependLines(klass.to_s.underline, TAB)
      items.sort_by{ |item, count| item.base_name }
           .group_by{ |item, count| item.slot }
           .sort_by{ |slot, slot_items| Schema.slotOrder.index(slot) }
           .each do |slot, slot_items|
          puts prependLines(SLOT[slot].underline("-"), TAB*2)
          slot_items.each { |item, count| puts(TAB*3 + "#{count}| #{item}") }
      end
  end
end

if(options[:friends])
  puts "\n" + "Getting friends' accounts".title
  friends = options[:friends].map{|i| SteamID[i]}.compact

  puts "\n" + "Getting friends' missing items".title
  could_give = Hash[
    friends.map{|friend|
      [friend, ItemSet[friend.missing.select{|i|
        trade.key?(i) && !trade[i].empty?}.map{|i| trade[i].pop}]]
  }]

  friends.each do |friend|
    puts
    puts "#{friend.real_name} [#{could_give[friend].size}]".underline

    could_give[friend].class_sort.each do |klass, items|
      puts prependLines(klass.to_s.underline, "\t")
      items.sort_by{|i| i.base_name}.each{|i| puts "\t\t#{i.name}"}
    end
  end
end

if(options[:scrap])
  puts "\n" + "Calculating scrap".title

  items = ItemSet[trade.values.flatten]
  craft = items.craft_combinations.sort do |a,b|
    f = a.first.name <=> b.first.name; f != 0 ? f : a.last.name <=> b.last.name
  end

  remaining = items.clone
  craft.each do |pair|
    pair.each do |i|
      remaining.delete_at(remaining.index{|j| j.index == i.index})
    end
  end

  puts "\nCraft combinations [#{craft.size}]".underline
  if(craft.empty?)
    puts "No crafting possible"
  else
    craft.each{|p| puts p.join(" + ")}
  end

  puts "\nValue in Metal".underline
  ref = craft.size/9.0
  puts ref.round(2).to_s + " ref"

  def ref_to_exact(ref)
    ref, rec = ref / 1, ref % 1
    rec, scr = rec / 0.33, rec % 0.33
    scr = scr / 0.11
    [ref, rec, scr].map{|i| i.to_i}
  end

  units = %w(ref rec scrap)
  puts ref_to_exact(ref).zip(units).select{|i| i[0] != 0}.map{|i| i.join(" ")}.join(", ")

  puts "\nRemaining Duplicates [#{remaining.size}]".underline
  puts remaining
end

require 'json'
require 'net/http'
require 'set'

# Get a Steam API key from http://steamcommunity.com/dev/apikey
# The script expects a file named 'apikey' with the apikey as its only contents.
APIKEY = File.open("apikey").read.chomp

class WebAPI
  class << self; attr_accessor :log, :json; end

  def self.key=(key)
    @@key = key
  end

  def self.key
    (defined?(@@key)) ? (@@key) : (raise "API Key not set.")
  end

  def self.call(interface, method, version, params=Hash.new)
    url = makeURL(interface, method, version, params)
    $stderr.puts("log:[#{url}]") if self.log
    response = Net::HTTP.get_response(URI.parse(url))
    json = JSON.parse(response.body)
    $stderr.puts("json:[\n#{json}\n]") if self.json
    json
  end

  private

  def self.makeURL(interface, method, vers, params)
    "http://api.steampowered.com/" +
      "#{interface}/#{method}/v#{vers.to_s.rjust(4,"0")}/" +
      "?key=#{WebAPI.key}&format=json" +
      params.map{|k,v| "&#{k}=#{v}"}.join
  end
end

class Schema
  def self.[](defindex)
    self.items.find{|i| i.index == defindex}
  end

  def self.items
    defined?(@@items) ? @@items : load
  end

  def self.update
    schema = WebAPI.call("IEconItems_440", "GetSchema", 1, "language" => "en")["result"]
    File.open("schema.obj", "w") {|f| f.write(JSON[schema])}
  end

  def self.load
    update unless File.exists?("schema.obj")
    schema = JSON.load(File.new("schema.obj", "r"))
    @@items = ItemSet[schema["items"].map{|i| Item.new(i)}]
  end

  def self.uniques
    stock = self.items.select{|i| i.weapon? and i.quality?("Normal")}
    exclude = /Botkiller|Token|Deflector|Festive|Saxxy|Promo/
    self.items.select{|i| !stock.any?{|s| s.name == i.name} and i.weapon? and i.quality?("Unique") and !((i.name + " " + i["name"]) =~ exclude)}
  end

  def self.classOrder
    @@ClassOrder.dup
  end

  def self.classRoleOrder
    @@ClassRoleOrder.dup
  end

  def self.slotOrder
    @@SlotOrder.dup
  end

  @@ClassOrder = ["All", "Scout", "Sniper", "Soldier", "Demoman", "Medic",
                  "Heavy", "Pyro", "Spy", "Engineer"]

  @@ClassRoleOrder = ["Scout", "Soldier", "Pyro", "Demoman", "Heavy",
                      "Engineer", "Medic", "Sniper", "Spy"]

  @@SlotOrder = ["none", "primary", "secondary", "melee", "pda",
                 "pda2", "head", "misc", "action"]
end

class SteamID
  attr_reader :steamid

  def self.[](nameOrId)
    self.guess(nameOrId)
  end

  def self.guess(nameOrId)
    (nameOrId.to_s =~ /^[0-9]{17}/) ? fromID(nameOrId) : fromName(nameOrId)
  end

  def self.fromName(name)
    SteamID.init(resolveVanityURL(name))
  end

  def self.fromID(steamid)
    SteamID.init(steamid)
  end

  def self.resolveVanityURL(name)
    result = WebAPI.call("ISteamUser", "ResolveVanityURL", 1, "vanityurl" => name)
    result["response"]["steamid"]
  end

  def name
    playerData["personaname"]
  end

  alias :to_s :name

  def real_name
    playerData["realname"] || name
  end

  def avatar_url
    playerData["avatarfull"]
  end

  def playerData
    @playerData ||= WebAPI.call("ISteamUser", "GetPlayerSummaries", 2, "steamids" => @steamid)["response"]["players"].first
  end

  def items
    @items || update_items
  end

  def missing
    Schema.uniques.reject{|id| items.any?{|item| item.index == id.index}}
  end

  def add_items(items)
    @items.add_items(items)
  end

  private

  def self.init(steamid)
    (steamid.to_s =~ /^[0-9]{17}/) ? SteamID.new(steamid) : nil
  end

  def initialize(steamid)
    @steamid = steamid.to_s
  end

  def update_items
    response = WebAPI.call("IEconItems_440", "GetPlayerItems", 1, "SteamID" => @steamid)["result"]
    if !response || response["status"] == 15
        items = []
        $stderr.puts("log:[Couldn't fetch items for #{@steamid}]")
    else
        items = response["items"].map{|i| PlayerItem.new(i)}
    end
    @items = ItemSet[items]
  end
end

class Item
  def initialize(item)
    @item = item
  end

  def [](i); @item[i]; end

  def name
    ((self["proper_name"]) ? "The " : "") +
      ((quality?("N") || quality?("U")) ? "" : "#{quality_name} ") +
      base_name
  end

  def base_name; self["item_name"]; end

  def index; self["defindex"]; end

  def weapon?
    %w(primary secondary melee pda pda2).include?(slot)
  end

  def cosmetic?
    %w(head misc action).include?(slot)
  end

  def == (item); self.index == item.index; end

  def raw; @item; end

  def quality; self["item_quality"];end
  def quality_name; @@Quality[quality][0]; end
  def quality_abbrev; @@Quality[quality][1]; end
  def quality?(q)
    [quality, quality_name, quality_abbrev].include?(q)
  end

  def classes
    c = self["used_by_classes"]
    (c.nil? || c.empty?) ? ["All"] : c
  end

  def slot
    s = self["item_slot"]
    (s.nil? || s.empty?) ? "none" : s
  end

  def to_s
    self.name
  end

  def inspect
    @item.inspect
  end

  @@Quality = {
    0 => %w(Normal N),
    1 => %w(Genuine G),
    3 => %w(Vintage V),
    5 => %w(Unusual !),
    6 => %w(Unique U),
    7 => %w(Community C),
    8 => %w(Valve *),
    9 => %w(Self-made ^),
    11 => %w(Strange S),
    13 => %w(Haunted H),
    255 => %w(Powerup P)
  }
end

class PlayerItem < Item
  def initialize(item)
    super(item)
  end

  def [](i); (@item.has_key? i) ? @item[i] : Schema[index][i]; end

  def will_trade?
    self.quality?("Unique") && !(self["flag_cannot_trade"])
  end

  def new?; self["inventory"] == 0; end

  def == (item); self["id"] == item["id"]; end

  def quality; self["quality"]; end

  def bp_slot; self["inventory"] & 0xFFFF; end
end

class ItemSet
  include Enumerable

  [:find_all, :select, :reject, :sort, :sort_by, :take, :take_while,
    :drop, :drop_while, :concat, :+, :<<, :grep, :delete_at, :clone, :dup].each{|method|
    define_method method do |*args, &block|
      ItemSet[@items.send(method, *args, &block)]
    end
  }

  [:each, :size, :empty?, :to_a, :to_ary, :entries, :[], :any?,
    :all?, :pop, :collect, :map, :collect_concat, :flat_map, :count,
    :detect, :find, :first, :find_index, :index, :include?, :inject, :max,
    :max_by, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :reduce, :zip].each{|method|
    define_method method do |*args, &block|
      @items.send(method, *args, &block)
    end
  }

  [:group_by].each{|method|
    define_method method do |*args, &block|
      Hash[@items.send(method, *args, &block).map{|k,v| [k,ItemSet[v]]}]
    end
  }

  [:partition].each{|method|
    define_method method do |*args, &block|
      @items.send(method, *args, &block).map{|i| ItemSet[i]}
    end
  }

  def initialize(items = [])
    @items = items
  end

  def self.[](items)
    ItemSet.new(items)
  end

  def backpack_sort
    self.sort_by{|i| i.bp_slot}
  end

  def class_sort
    by_min_class.to_a.sort_by{|klass, items| Schema.classOrder.index(klass)}
  end

  def by_class
    result = Hash.new{|h,i| h[i] = ItemSet.new}
    self.each{|item|
      item.classes.each{|klass| result[klass] << item}
    }
    result
  end

  def duplicates
    Hash[group_by{|item| item.index}.
      map{|index, group| [Schema[index], group]}.
      select{|index, group| group.size > 1}
    ]
  end

  def craft_combinations
    def helper(sets, memo = Hash.new)
      sets = sets.select{|k,v| v > 0}
      str = sets.to_s
      if memo[str]
        return memo[str]
      elsif sets.empty?
        return []
      else
        s, _ = sets.first
        sets[s] -= 1
        cand = sets.select{|t,d| !(s & t).empty? && d > 0}
        poss = cand.map{|t,d|
          tmp = sets.dup
          tmp[t] -= 1
          [[s,t]] + helper(tmp, memo)}
        result = poss.max_by{|i| i.size} || helper(sets, memo)
        memo[str] = result
        return result
      end
    end

    byclass = sort_by{|i| i.name}.group_by{|i| Set.new(i.classes.map{|c| c.to_sym})}

    combs = helper(Hash[byclass.map{|w,ws| [w, ws.size]}])
    combs.map{|s,t| [s,t].map{|u| byclass[u].pop}.sort_by{|i| i.name}}
  end

  private

  def by_min_class
    result = Hash.new{|h,i| h[i] = ItemSet.new}
    self.each{|item| result[min_class(item.classes)] << item}
    result
  end

  def min_class(classes)
    classes.min_by{|i| Schema.classOrder.index(i)}
  end
end

WebAPI.key = APIKEY

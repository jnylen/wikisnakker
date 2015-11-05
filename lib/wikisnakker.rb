require 'wikisnakker/version'

require 'colorize'
require 'digest/md5'
require 'pry'
require 'open-uri/cached'
require 'json'
require 'set'

module Wikisnakker

  class Lookup

    def initialize(ids, resolve=true)
      @_used_props = Set.new
      @_hash = ids.compact.uniq.each_slice(50).map { |sliced|
        page_args = {
          action: 'wbgetentities',
          ids: sliced.join("|"),
          format: 'json',
        }
        url = 'https://www.wikidata.org/w/api.php?' + URI.encode_www_form(page_args)
        # warn "Fetching #{url}"

        # If a property is set to another Wikidata article, resolve that
        # (e.g. set 'gender' to 'male' rather than 'Q6581097')
        # We don't know yet what that will resolve to, and we don't want
        # to look them up one by one, so store a promise and bulk-resolve
        # when done
        json = JSON.load(open(url).read, lambda { |h|
          if h.class == Hash and h['type'] == 'wikibase-entityid'
            @_used_props << h['value']['numeric-id']
            h['resolved'] = lambda { prop(h['value']['numeric-id']) }
          end
        })
        json['entities']
      }.reduce(&:merge)

      if resolve
        props = Lookup.new(@_used_props.to_a.map { |e| "Q#{e}" }, false)
        # This relies on the Property being described in 'en', but I think that's safe
        @pmap = Hash[ props.all.map { |k, v| [k, v['labels']['en']['value']] } ]
      end
    end

    def all
      all = @_hash
    end

    def values
      @_hash.values
    end

    def prop(id)
      @pmap[ "Q#{id.to_s.sub('P','')}" ]
    end

  end

  class Item

    def self.find(ids)
      _ids = [ids].flatten
      lookup = Lookup.new(_ids)
      data = lookup.values
      inflated = data.map { |rd| self.new(rd) }
      _ids.size == 1 ? inflated.first : inflated
    end

    def initialize(raw)
      @_raw = raw
    end

    def method_missing(name)
      handle = name.to_s.upcase.match(/P(\d+)(S?)/) or return
      pid, wantarray = handle.captures
      res = p(pid)
      wantarray.empty? ? p(pid).first : p(pid)
    end

    def id
      @_raw['title']
    end

    def _raw
      @_raw
    end

    def labels
      @_raw['labels']
    end

    def label(lang)
      labels[lang]['value']
    end

    def p(pid)
      (@_raw['claims']["P#{pid}"] || []).map { |c| Claim.new(c) }
    end

  end

  class Claim

    def initialize(data)
      @data = data
    end

    def value
      mainsnak.value
    end

    def to_s
      mainsnak.value
    end

    def mainsnak
      @_mainsnak ||= Snak.new( @data["mainsnak"] )
    end

  end

  class Snak

    def initialize(snak)
      @snak = snak
    end

    # https://www.wikidata.org/wiki/Special:ListDatatypes
    # https://www.wikidata.org/wiki/Help:Data_type
    def value
      case @snak['datatype']
      when 'commonsMedia'
        # https://commons.wikimedia.org/wiki/Commons:FAQ#What_are_the_strangely_named_components_in_file_paths.3F
        # commons = 'https://commons.wikimedia.org/wiki/File:%s' % @snak["datavalue"]["value"]
        md5 = Digest::MD5.hexdigest @snak["datavalue"]["value"]
        'https://upload.wikimedia.org/wikipedia/commons/%s/%s/%s' % [md5[0], md5[0..1], @snak["datavalue"]["value"]]
      when 'globe-coordinate'
        # Not implemented yet
        binding.pry
      when 'wikibase-item'
        # "Q%s" % @snak["datavalue"]["value"]["numeric-id"]
        @snak["datavalue"]["resolved"].call
      when 'wikibase-property'
        # Not implemented yet
        binding.pry
      when 'string'
        @snak["datavalue"]["value"]
      when 'monolingualtext'
        # Not implemented yet
        binding.pry
      when 'quantity'
        if @snak["datavalue"]["value"]["upperBound"] == @snak["datavalue"]["value"]["lowerBound"]
          @snak["datavalue"]["value"]["amount"].to_i
        else
          binding.pry
        end
      when 'time'
        case @snak["datavalue"]["value"]["precision"]
        when 11
          @snak["datavalue"]["value"]["time"][1..10]
        else
          binding.pry
        end
      when 'url'
        # Not implemented yet
        binding.pry
      else
        warn "Unknown datatype: #{@snak['datatype']}"
        binding.pry
      end
    end
  end
end
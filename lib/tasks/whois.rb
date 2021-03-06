module Intrigue
module Task
class Whois < BaseTask
  include Intrigue::Task::Web

  def self.metadata
    {
      :name => "whois",
      :pretty_name => "Whois",
      :authors => ["jcran"],
      :description => "Perform a whois lookup for a given entity",
      :references => [],
      :type => "discovery",
      :passive => true,
      :allowed_types => ["DnsRecord","IpAddress","NetBlock"],
      :example_entities => [
        {"type" => "DnsRecord", "details" => {"name" => "intrigue.io"}},
        {"type" => "IpAddress", "details" => {"name" => "192.0.78.13"}},
      ],
      :allowed_options => [
        {:name => "timeout", :type => "Integer", :regex=> "integer", :default => 20 },
        {:name => "create_contacts", :type => "Boolean", :regex => "boolean", :default => true },
        {:name => "create_nameservers", :type => "Boolean", :regex => "boolean", :default => true }
      ],
      :created_types => ["EmailAddress", "NetBlock", "Person"]
    }
  end

  ## Default method, subclasses must override this
  def run
    super

    ###
    ### XXX - doesn't currently respect the timeout
    ###

    lookup_string = _get_entity_name
    opt_create_nameservers = _get_option "create_nameservers"
    opt_create_contacts = _get_option "create_contacts"

    begin
      whois = ::Whois::Client.new(:timeout => 20)
      answer = whois.lookup(lookup_string)
      parser = answer.parser
      whois_full_text = answer.content if answer
    rescue ::Whois::ResponseIsThrottled => e
      _log_error "Unable to query whois: #{e}"
      return
    rescue Timeout::Error => e
      _log_error "Unable to query whois: #{e}"
      return
    end

    #
    # Check first to see if we got an answer back
    #
    if answer

      # Log the full text of the answer
      _log "== Full Text: =="
      _log answer.content
      _log "================"

      ripe = true if answer.content =~ /RIPE/

      #
      # if it was a domain, we've got a whole lot of things we can pull
      #
      if lookup_string.is_ip_address? && !ripe

        #
        # Otherwise our entity must've been a host, so lets connect to
        # ARIN's API and fetch the details
        begin
          doc = Nokogiri::XML(http_get_body("http://whois.arin.net/rest/ip/#{lookup_string}"))
          org_ref = doc.xpath("//xmlns:orgRef").text
          parent_ref = doc.xpath("//xmlns:parentNetRef").text
          handle = doc.xpath("//xmlns:handle").text

          # For each netblock, create an entity
          doc.xpath("//xmlns:netBlocks").children.each do |netblock|
            # Grab the relevant info

            cidr_length = ""
            start_address = ""
            end_address = ""
            block_type = ""
            description = ""

            netblock.children.each do |child|

              cidr_length = child.text if child.name == "cidrLength"
              start_address = child.text if child.name == "startAddress"
              end_address = child.text if child.name == "endAddress"
              block_type = child.text if child.name == "type"
              description = child.text if child.name == "description"

            end # End netblock children

            #
            # Create the netblock entity
            #
            entity = _create_entity "NetBlock", {
              "name" => "#{start_address}/#{cidr_length}",
              "start_address" => "#{start_address}",
              "end_address" => "#{end_address}",
              "cidr" => "#{cidr_length}",
              "description" => "#{description}",
              "block_type" => "#{block_type}",
              "handle" => "#{handle}",
              "organization_reference" => "#{org_ref}",
              "parent_reference" => "#{parent_ref}",
              "whois_full_text" => "#{answer.content}",
              "rir" => "ARIN"
            }

          end # End Netblocks
        rescue Nokogiri::XML::XPath::SyntaxError => e
          _log_error "Got an error while parsing the XML: #{e}"
        end

      # If we detected that this is a RIPE-allocated range, let's connect to
      # their stat.ripe.net API and pull the details
      elsif lookup_string.is_ip_address? && ripe

        ripe_uri = "https://stat.ripe.net/data/address-space-hierarchy/data.json?resource=#{lookup_string}/32"
        json = JSON.parse(http_get_body(ripe_uri))

        # set entity details
        _log "Got JSON from #{ripe_uri}:"
        _log "#{json}"

        range = json["data"]["last_updated"].first["ip_space"]

        entity = _create_entity "NetBlock", {
          "name" => "#{range}",
          "cidr" => "#{range.split('/').last}",
          "description" => json["data"]["netname"],
          "rir" => "RIPE",
          "organization_reference" => json["data"]["org"],
          "whois_full_text" => "#{answer.content}"
        }

      else

        #
        # We're going to have nameservers either way?
        #
        begin
          if parser.nameservers
            if opt_create_nameservers
              parser.nameservers.each do |nameserver|
                _log "Parsed nameserver: #{nameserver}"
                _create_entity "DnsRecord", "name" => nameserver.to_s
              end
            else
              _log "Skipping nameservers"
            end
          else
            _log_error "No parsed nameservers!"
            return
          end

          #
          # Create a user from the technical contact
          #
          if opt_create_contacts
            parser.contacts.each do |contact|
              _log "Creating user from contact: #{contact.name}"
              _create_entity("Person", {"name" => contact.name})
              _create_entity("EmailAddress", {"name" => contact.email})
            end
          else
            _log "Skipping contacts"
          end
        rescue ::Whois::AttributeNotImplemented => e
          _log_error "Unable to parse that attribute: #{e}"
        end

      end # end Host Type

    else
      _log_error "Domain WHOIS failed, we don't know what nameserver to query."

    end

  end

end
end
end

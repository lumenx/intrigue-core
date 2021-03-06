module Intrigue
module Task
class WebAccountCheck < BaseTask

  include Intrigue::Task::Web

  def self.metadata
    {
      :name => "web_account_check",
      :pretty_name => "Web Account Check",
      :authors => ["jcran"],
      :description => "This task hits major websites, checking for the existence of accounts. Discovered accounts are created.",
      :references => [],
      :type => "discovery",
      :passive => true,
      :allowed_types => ["String","Person","Organization","Username","WebAccount"],
      :example_entities => [{"type" => "String", "details" => {"name" => "intrigueio"}}],
      :allowed_options => [
        {:name => "specific_sites", :type => "String", :regex => "alpha_numeric_list", :default => "" }
      ],
      :created_types => ["WebAccount"]
    }
  end

  ## Default method, subclasses must override this
  def run
    super

    account_name = _get_entity_name
    opt_specific_sites = _get_option "specific_sites"

    check_file = "data/web_accounts_list/web_accounts_list.json"

    unless File.exists? check_file
      _log_error "#{check_file} does not exist. Did you run the script in data/ ?"
      return
    end

    account_list_data = File.open(check_file).read
    account_list = JSON.parse(account_list_data)


    _log "Checking target against #{account_list["sites"].count} possible sites"

    account_list["sites"].each do |site|

      # This allows us to only check specific sites - good for testing
      unless opt_specific_sites == ""
        next unless opt_specific_sites.split(",").include? site["name"]
      end

      # craft the uri with our entity's properties
      account_uri = site["check_uri"].gsub("{account}",account_name)
      pretty_uri = site["pretty_uri"].gsub("{account}",account_name) if site["pretty_uri"]

      # Skip if the site tags don't match our type
      unless site["allowed_types"].include? @entity.type_string
        _log "Skipping #{account_uri}, doesn't match our type"
        next
      end

      # Otherwise, go get it
      _log "Checking #{account_uri}"
      body = http_get_body(account_uri)
      next unless body

      # Check the verify string
      if body.include? site["account_existence_string"]
        _create_entity "WebAccount", {
            "name" => "#{account_name} on #{site["name"]}",
            "domain" => "#{site["name"]}",
            "username" => "#{account_name}",
            "uri" => "#{pretty_uri || account_uri}"
           }
      end

    end

  end # run()

end # ProfileSearch
end
end

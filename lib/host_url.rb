#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class HostUrl
  class << self
    attr_accessor :outgoing_email_address, :outgoing_email_domain, :outgoing_email_default_name

    @@default_host = nil
    @@file_host = nil
    @@domain_config = nil

    def context_host(context=nil)
      default_host
    end
    
    def default_host
      if !@@default_host
        @@domain_config ||= File.exist?("#{RAILS_ROOT}/config/domain.yml") && YAML.load_file("#{RAILS_ROOT}/config/domain.yml")[RAILS_ENV].with_indifferent_access
        @@default_host = @@domain_config[:domain] if @@domain_config && @@domain_config.has_key?(:domain)
      end
      res = @@default_host
      res ||= ENV['RAILS_HOST_WITH_PORT']
      res
    end
    
    def file_host(account)
      return @@file_host if @@file_host
      res = nil
      @@domain_config ||= File.exist?("#{RAILS_ROOT}/config/domain.yml") && YAML.load_file("#{RAILS_ROOT}/config/domain.yml")[RAILS_ENV].with_indifferent_access
      res = @@file_host = @@domain_config[:files_domain] if @@domain_config && @@domain_config.has_key?(:files_domain)
      Rails.logger.warn("No separate files host specified for account id #{account.id}.  This is a potential security risk.") unless res || !Rails.env.production?
      res ||= @@file_host = default_host
    end
    
    def short_host(context)
      context_host(context)
    end
    
    def outgoing_email_address(preferred_user="notifications")
      @outgoing_email_address.presence || "#{preferred_user}@#{outgoing_email_domain}"
    end

    def outgoing_email_default_name
      @outgoing_email_default_name.presence || I18n.t("#email.default_from_name", "Instructure Canvas")
    end

    def file_host=(val)
      @@file_host = val
    end
    def default_host=(val)
      @@default_host = val
    end
    
    def is_file_host?(domain)
      safer_host = file_host(Account.default)
      safer_host != default_host && domain == safer_host
    end
  end
end

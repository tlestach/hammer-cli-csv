# Copyright (c) 2013-2014 Red Hat
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'hammer_cli'
require 'katello_api'
require 'json'
require 'csv'

module HammerCLICsv
  class UsersCommand < BaseCommand

    FIRSTNAME = 'First Name'
    LASTNAME = 'Last Name'
    EMAIL = 'Email'
    ORGANIZATIONS = 'Organizations'
    LOCATIONS = 'Locations'
    ROLES = 'Roles'

    def export
      CSV.open(option_csv_file || '/dev/stdout', 'wb', {:force_quotes => true}) do |csv|
        csv << [NAME, COUNT, FIRSTNAME, LASTNAME, EMAIL, ORGANIZATIONS, LOCATIONS, ROLES]
        @f_user_api.index({:per_page => 999999})[0]['results'].each do |user|
          organizations = CSV.generate do |column|
            column << user['organizations'].collect do |organization|
              organization['name']
            end
          end.delete!("\n") if user['organizations']
          locations = CSV.generate do |column|
            column << user['locations'].collect do |location|
              location['name']
            end
          end.delete!("\n") if user['locations']
          roles = CSV.generate do |column|
            column << user['roles'].collect do |role|
              role['name']
            end
          end.delete!("\n") if user['roles']
          if user['login'] != 'admin' && !user['login'].start_with?('hidden-')
            csv << [user['login'], 1, user['firstname'], user['lastname'], user['mail'], organizations, locations, roles]
          end
        end
      end
    end

    def import
      @existing = {}
      @f_user_api.index({:per_page => 999999})[0]['results'].each do |user|
        @existing[user['login']] = user['id'] if user
      end

      thread_import do |line|
        create_users_from_csv(line)
      end
    end

    def create_users_from_csv(line)
      line[COUNT].to_i.times do |number|
        name = namify(line[NAME], number)

        roles = CSV.parse_line(line[ROLES], {:skip_blanks => true}).collect do |role|
          foreman_role(:name => namify(role, number))
        end if line[ROLES]
        organizations = CSV.parse_line(line[ORGANIZATIONS], {:skip_blanks => true}).collect do |organization|
          foreman_organization(:name => organization)
        end if line[ORGANIZATIONS]
        locations = CSV.parse_line(line[LOCATIONS], {:skip_blanks => true}).collect do |location|
          foreman_location(:name => location)
        end if line[LOCATIONS]

        if !@existing.include? name
          print "Creating user '#{name}'... " if option_verbose?
          @f_user_api.create({
                               'user' => {
                                 'login' => name,
                                 'firstname' => line[FIRSTNAME],
                                 'lastname' => line[LASTNAME],
                                 'mail' => line[EMAIL],
                                 'password' => 'changeme',
                                 'auth_source_id' => 1,  # INTERNAL auth
                                 'organization_ids' => organizations,
                                 'location_ids' => locations,
                                 'role_ids' => roles
                               }
                             })
        else
          print "Updating user '#{name}'... " if option_verbose?
          @f_user_api.update({
                               'id' => @existing[name],
                               'user' => {
                                 'login' => name,
                                 'firstname' => line[FIRSTNAME],
                                 'lastname' => line[LASTNAME],
                                 'mail' => line[EMAIL],
                                 'password' => 'changeme',
                                 'organization_ids' => organizations,
                                 'location_ids' => locations,
                                 'role_ids' => roles
                               }
                             })
        end
        print "done\n" if option_verbose?
      end
    rescue RuntimeError => e
      raise "#{e}\n       #{line}"
    end
  end

  HammerCLI::MainCommand.subcommand("csv:users", "import or export users as CSV", HammerCLICsv::UsersCommand)
end

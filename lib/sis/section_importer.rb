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

module SIS
  class SectionImporter < SisImporter
    EXPECTED_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"
    
    def self.is_section_csv?(row)
      #This matcher works because an enrollment doesn't have  name
      row.header?('section_id') && row.header?('name')
    end
    
    def verify(csv, verify)
      # section ids must be unique across the account
      section_ids = (verify[:sections_id] ||= {})
      csv_rows(csv) do |row|
        section_id = row['section_id']
        course_id = row['course_id']
        add_error(csv, "Duplicate section id #{section_id}") if section_ids[section_id]
        section_ids[section_id] = true
        add_error(csv, "No section_id given for a section in course #{course_id}") if section_id.blank?
        add_error(csv, "No course_id given for a section #{section_id}") if course_id.blank?
        add_error(csv, "No name given for section #{section_id} in course #{course_id}") if row['name'].blank?
        add_error(csv, "Improper status \"#{row['status']}\" for section #{section_id} in course #{course_id}") unless row['status'] =~ /\Aactive|\Adeleted/i
      end
    end
    
    # expected columns
    # section_id,course_id,name,status,start_date,end_date
    def process(csv)
      start = Time.now
      sections_to_update_sis_batch_ids = []
      course_ids_to_update_associations = [].to_set

      csv_rows(csv) do |row|
        update_progress
        
        Course.skip_updating_account_associations do
          logger.debug("Processing Section #{row.inspect}")

          course = Course.find_by_root_account_id_and_sis_source_id(@root_account.id, row['course_id'])
          unless course
            add_warning(csv,"Section #{row['section_id']} references course #{row['course_id']} which doesn't exist")
            next
          end

          name = row['name']
          section = CourseSection.find_by_root_account_id_and_sis_source_id(@root_account.id, row['section_id'])
          section ||= course.course_sections.find_by_sis_source_id(row['section_id'])
          section ||= course.course_sections.new
          section.root_account = @root_account
          # this is an easy way to load up the cache with data we already have
          section.course = course if course.id == section.course_id

          section.account = row['account_id'].present? ? Account.find_by_root_account_id_and_sis_source_id(@root_account.id, row['account_id']) : nil
          course_ids_to_update_associations.add section.course_id if section.account_id_changed?

          # only update the name on new records, and ones that haven't been changed since the last sis import
          if section.new_record? || (section.sis_name && section.sis_name == section.name)
            section.name = section.sis_name = row['name']
          end

          # update the course id if necessary
          if section.course_id != course.id
            if section.nonxlist_course_id
              # this section is crosslisted
              if section.nonxlist_course_id != course.id
                # but the course id we were given didn't match the crosslist info
                # we have, so, uncrosslist and move
                course_ids_to_update_associations.merge [course.id, section.course_id, section.nonxlist_course_id]
                section.uncrosslist(:run_jobs_immediately)
                section.move_to_course(course, :run_jobs_immediately)
              end
            else
              # this section isn't crosslisted and lives on the wrong course. move
              course_ids_to_update_associations.merge [section.course_id, course.id]
              section.move_to_course(course, :run_jobs_immediately)
            end
          end

          course_ids_to_update_associations.add section.course_id

          section.sis_source_id = row['section_id']
          if row['status'] =~ /active/i
            section.workflow_state = 'active'
          elsif row['status'] =~ /deleted/i
            section.workflow_state = 'deleted'
          end

          begin
            section.start_at = row['start_date'].blank? ? nil : DateTime.parse(row['start_date'])
            section.end_at = row['end_date'].blank? ? nil : DateTime.parse(row['end_date'])
          rescue
            add_warning(csv, "Bad date format for section #{row['section_id']}")
          end
          section.restrict_enrollments_to_section_dates = (section.start_at.present? || section.end_at.present?)

          if section.changed?
            section.sis_batch_id = @batch.id if @batch
            section.save
          elsif @batch
            sections_to_update_sis_batch_ids << section.id
          end

          @sis.counts[:sections] += 1
        end
      end
      Course.update_account_associations(course_ids_to_update_associations.to_a) unless course_ids_to_update_associations.empty?

      CourseSection.update_all({:sis_batch_id => @batch.id}, {:id => sections_to_update_sis_batch_ids}) if @batch && !sections_to_update_sis_batch_ids.empty?
      logger.debug("Sections took #{Time.now - start} seconds")
    end
  end
end

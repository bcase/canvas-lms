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

require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../views_helper')

describe "/groups/show" do
  it "should render" do
    course_with_student
    @group = @course.groups.create!(:name => "some group")
    view_context(@group, @user)
    assigns[:group] = @group
    assigns[:topics] = []
    assigns[:upcoming_events] = []
    assigns[:recent_events] = []
    assigns[:context] = @group
    render "groups/show"
    response.should_not be_nil
  end
end


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

require File.expand_path(File.dirname(__FILE__) + '/../api_spec_helper')

describe ConversationsController, :type => :integration do
  before do
    course_with_teacher(:active_course => true, :active_enrollment => true, :user => user_with_pseudonym(:active_user => true))
    @course.update_attribute(:name, "the course")
    @me = @user

    @bob = student_in_course(:name => "bob")
    @billy = student_in_course(:name => "billy")
    @jane = student_in_course(:name => "jane")
    @joe = student_in_course(:name => "joe")
    @tommy = student_in_course(:name => "tommy")
  end

  def student_in_course(options = {})
    u = User.create(options)
    enrollment = @course.enroll_student(u)
    enrollment.workflow_state = 'active'
    enrollment.save
    u.associated_accounts << Account.default
    u
  end

  def conversation(*users)
    options = users.last.is_a?(Hash) ? users.pop : {}
    @conversation = (options.delete(:sender) || @me).initiate_conversation(users.map(&:id))
    @conversation.add_message('test')
    @conversation.update_attributes(options)
    @conversation.reload
  end

  context "conversations" do
    it "should return the conversation list" do
      @c1 = conversation(@bob, :workflow_state => 'read', :label => "blue")
      @c2 = conversation(@bob, @billy, :workflow_state => 'unread', :subscribed => false)
      @c3 = conversation(@jane, :workflow_state => 'archived') # won't show up, since it's archived

      json = api_call(:get, "/api/v1/conversations.json",
              { :controller => 'conversations', :action => 'index', :format => 'json' })
      json.each { |c| c.delete("avatar_url") } # this URL could change, we don't care
      json.should eql [
        {
          "id" => @c2.conversation_id,
          "workflow_state" => "unread",
          "last_message" => "test",
          "last_message_at" => @c2.last_message_at.to_json[1, 20],
          "message_count" => 1,
          "subscribed" => false,
          "private" => false,
          "label" => nil,
          "properties" => ["last_author"],
          "audience" => [@billy.id, @bob.id],
          "audience_contexts" => {
            "groups" => {},
            "courses" => {@course.id.to_s => []}
          },
          "participants" => [
            {"id" => @me.id, "name" => @me.name},
            {"id" => @billy.id, "name" => @billy.name},
            {"id" => @bob.id, "name" => @bob.name}
          ]
        },
        {
          "id" => @c1.conversation_id,
          "workflow_state" => "read",
          "last_message" => "test",
          "last_message_at" => @c1.last_message_at.to_json[1, 20],
          "message_count" => 1,
          "subscribed" => true,
          "private" => true,
          "label" => "blue",
          "properties" => ["last_author"],
          "audience" => [@bob.id],
          "audience_contexts" => {
            "groups" => {},
            "courses" => {@course.id.to_s => ["StudentEnrollment"]}
          },
          "participants" => [
            {"id" => @me.id, "name" => @me.name},
            {"id" => @bob.id, "name" => @bob.name}
          ]
        }
      ]
    end

    it "should paginate and return proper pagination headers" do
      7.times{ conversation(student_in_course) }
      @user.conversations.size.should eql 7
      json = api_call(:get, "/api/v1/conversations.json?scope=default&per_page=3",
                      {:controller => 'conversations', :action => 'index', :format => 'json', :scope => 'default', :per_page => '3'})

      json.size.should eql 3
      response.headers['Link'].should eql(%{</api/v1/conversations.json?scope=default&page=2&per_page=3>; rel="next",</api/v1/conversations.json?scope=default&page=1&per_page=3>; rel="first",</api/v1/conversations.json?scope=default&page=3&per_page=3>; rel="last"})

      # get the last page
      json = api_call(:get, "/api/v1/conversations.json?scope=default&page=3&per_page=3",
                      {:controller => 'conversations', :action => 'index', :format => 'json', :scope => 'default', :page => '3', :per_page => '3'})
      json.size.should eql 1
      response.headers['Link'].should eql(%{</api/v1/conversations.json?scope=default&page=2&per_page=3>; rel="prev",</api/v1/conversations.json?scope=default&page=1&per_page=3>; rel="first",</api/v1/conversations.json?scope=default&page=3&per_page=3>; rel="last"})
    end

    it "should filter conversations by scope" do
      @c1 = conversation(@bob, :workflow_state => 'read', :label => "blue")
      @c2 = conversation(@bob, @billy, :workflow_state => 'unread', :subscribed => false, :label => "green")
      @c3 = conversation(@jane, :workflow_state => 'read')

      json = api_call(:get, "/api/v1/conversations.json?scope=labeled&label=green",
              { :controller => 'conversations', :action => 'index', :format => 'json', :scope => 'labeled', :label => 'green' })
      json.each { |c| c.delete("avatar_url") }
      json.should eql [
        {
          "id" => @c2.conversation_id,
          "workflow_state" => "unread",
          "last_message" => "test",
          "last_message_at" => @c2.last_message_at.to_json[1, 20],
          "message_count" => 1,
          "subscribed" => false,
          "private" => false,
          "label" => "green",
          "properties" => ["last_author"],
          "audience" => [@billy.id, @bob.id],
          "audience_contexts" => {
            "groups" => {},
            "courses" => {@course.id.to_s => []}
          },
          "participants" => [
            {"id" => @me.id, "name" => @me.name},
            {"id" => @billy.id, "name" => @billy.name},
            {"id" => @bob.id, "name" => @bob.name}
          ]
        }
      ]
    end

    it "should mark all conversations as read" do
      @c1 = conversation(@bob, :workflow_state => 'unread')
      @c2 = conversation(@bob, @billy, :workflow_state => 'unread')
      @c3 = conversation(@jane, :workflow_state => 'archived')

      json = api_call(:post, "/api/v1/conversations/mark_all_as_read.json",
              { :controller => 'conversations', :action => 'mark_all_as_read', :format => 'json' })
      json.should eql({})

      @me.conversations.unread.size.should eql 0
      @me.conversations.default.size.should eql 2
      @me.conversations.archived.size.should eql 1
    end

    context "create" do
      it "should create a private conversation" do
        json = api_call(:post, "/api/v1/conversations",
                { :controller => 'conversations', :action => 'create', :format => 'json' },
                { :recipients => [@bob.id], :body => "test" })
        json.each { |c|
          c.delete("avatar_url")
          c["participants"].each{ |p|
            p.delete("avatar_url")
          }
        }
        conversation = @me.conversations.first
        json.should eql [
          {
            "id" => conversation.conversation_id,
            "workflow_state" => "read",
            "last_message" => "test",
            "last_message_at" => conversation.last_message_at.to_json[1, 20],
            "message_count" => 1,
            "subscribed" => true,
            "private" => true,
            "label" => nil,
            "properties" => ["last_author"],
            "audience" => [@bob.id],
            "audience_contexts" => {
              "groups" => {},
              "courses" => {@course.id.to_s => ["StudentEnrollment"]}
            },
            "participants" => [
              {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
              {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
            ],
            "messages" => [
              {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "test", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
            ]
          }
        ]
      end

      it "should create a group conversation" do
        json = api_call(:post, "/api/v1/conversations",
                { :controller => 'conversations', :action => 'create', :format => 'json' },
                { :recipients => [@bob.id, @billy.id], :body => "test", :group_conversation => true })
        json.each { |c|
          c.delete("avatar_url")
          c["participants"].each{ |p|
            p.delete("avatar_url")
          }
        }
        conversation = @me.conversations.first
        json.should eql [
          {
            "id" => conversation.conversation_id,
            "workflow_state" => "read",
            "last_message" => "test",
            "last_message_at" => conversation.last_message_at.to_json[1, 20],
            "message_count" => 1,
            "subscribed" => true,
            "private" => false,
            "label" => nil,
            "properties" => ["last_author"],
            "audience" => [@billy.id, @bob.id],
            "audience_contexts" => {
              "groups" => {},
              "courses" => {@course.id.to_s => []}
            },
            "participants" => [
              {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
              {"id" => @billy.id, "name" => @billy.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
              {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
            ],
            "messages" => [
              {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "test", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
            ]
          }
        ]
      end

      it "should update the private conversation if it already exists" do
        # set up a private conversation in advance
        conversation = conversation(@bob)

        json = api_call(:post, "/api/v1/conversations",
                { :controller => 'conversations', :action => 'create', :format => 'json' },
                { :recipients => [@bob.id], :body => "test" })
        conversation.reload
        json.each { |c|
          c.delete("avatar_url")
          c["participants"].each{ |p|
            p.delete("avatar_url")
          }
        }
        json.should eql [
          {
            "id" => conversation.conversation_id,
            "workflow_state" => "read",
            "last_message" => "test",
            "last_message_at" => conversation.last_message_at.to_json[1, 20],
            "message_count" => 2, # two messages total now, though we'll only get the latest one in the response
            "subscribed" => true,
            "private" => true,
            "label" => nil,
            "properties" => ["last_author"],
            "audience" => [@bob.id],
            "audience_contexts" => {
              "groups" => {},
              "courses" => {@course.id.to_s => ["StudentEnrollment"]}
            },
            "participants" => [
              {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
              {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
            ],
            "messages" => [
              {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "test", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
            ]
          }
        ]
      end

      it "should create/update bulk private conversations" do
        # set up one private conversation in advance
        conversation(@bob)

        json = api_call(:post, "/api/v1/conversations",
                { :controller => 'conversations', :action => 'create', :format => 'json' },
                { :recipients => [@bob.id, @joe.id, @billy.id], :body => "test" })
        json.size.should eql 1
        json[0]["id"].should eql @me.conversations.first.conversation_id

        @me.all_conversations.size.should eql(3)
        @me.conversations.size.should eql(1) # just the initial conversation with bob is visible to @me
        @bob.conversations.size.should eql(1)
        @billy.conversations.size.should eql(1)
        @joe.conversations.size.should eql(1)
      end

      it "should create a conversation with forwarded messages" do
        forwarded_message = conversation(@me, :sender => @bob).messages.first

        json = api_call(:post, "/api/v1/conversations",
                { :controller => 'conversations', :action => 'create', :format => 'json' },
                { :recipients => [@billy.id], :body => "test", :forwarded_message_ids => [forwarded_message.id] })
        json.each { |c|
          c.delete("avatar_url")
          c["participants"].each{ |p|
            p.delete("avatar_url")
          }
        }
        conversation = @me.conversations.first
        json.should eql [
          {
            "id" => conversation.conversation_id,
            "workflow_state" => "read",
            "last_message" => "test",
            "last_message_at" => conversation.last_message_at.to_json[1, 20],
            "message_count" => 1,
            "subscribed" => true,
            "private" => true,
            "label" => nil,
            "properties" => ["last_author"],
            "audience" => [@billy.id],
            "audience_contexts" => {
              "groups" => {},
              "courses" => {@course.id.to_s => ["StudentEnrollment"]}
            },
            "participants" => [
              {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
              {"id" => @billy.id, "name" => @billy.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
              {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
            ],
            "messages" => [
              {
                "id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "test", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "attachments" => [],
                "forwarded_messages" => [
                  {
                    "id" => forwarded_message.id, "created_at" => forwarded_message.created_at.to_json[1, 20], "body" => "test", "author_id" => @bob.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []
                  }
                ]
              }
            ]
          }
        ]
      end
    end
  end

  context "find_recipients" do
    before do
      @group = @course.groups.create(:name => "the group")
      @group.users = [@me, @bob, @joe]
    end

    it "should return recipients" do
      json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=o",
              { :controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'o' })
      json.each { |c| c.delete("avatar_url") }
      json.should eql [
        {"id" => "course_#{@course.id}", "name" => "the course", "type" => "context", "user_count" => 6},
        {"id" => "group_#{@group.id}", "name" => "the group", "type" => "context", "user_count" => 3},
        {"id" => @bob.id, "name" => "bob", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {@group.id.to_s => ["Member"]}},
        {"id" => @joe.id, "name" => "joe", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {@group.id.to_s => ["Member"]}},
        {"id" => @me.id, "name" => @me.name, "common_courses" => {@course.id.to_s => ["TeacherEnrollment"]}, "common_groups" => {@group.id.to_s => ["Member"]}},
        {"id" => @tommy.id, "name" => "tommy", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
      ]
    end

    it "should return recipients for a given course" do
      json = api_call(:get, "/api/v1/conversations/find_recipients.json?context=course_#{@course.id}",
              { :controller => 'conversations', :action => 'find_recipients', :format => 'json', :context => "course_#{@course.id}" })
      json.each { |c| c.delete("avatar_url") }
      json.should eql [
        {"id" => @billy.id, "name" => "billy", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
        {"id" => @bob.id, "name" => "bob", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
        {"id" => @jane.id, "name" => "jane", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
        {"id" => @joe.id, "name" => "joe", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
        {"id" => @me.id, "name" => @me.name, "common_courses" => {@course.id.to_s => ["TeacherEnrollment"]}, "common_groups" => {}},
        {"id" => @tommy.id, "name" => "tommy", "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
      ]
    end

    it "should return recipients for a given group" do
      json = api_call(:get, "/api/v1/conversations/find_recipients.json?context=group_#{@group.id}",
              { :controller => 'conversations', :action => 'find_recipients', :format => 'json', :context => "group_#{@group.id}" })
      json.each { |c| c.delete("avatar_url") }
      json.should eql [
        {"id" => @bob.id, "name" => "bob", "common_courses" => {}, "common_groups" => {@group.id.to_s => ["Member"]}},
        {"id" => @joe.id, "name" => "joe", "common_courses" => {}, "common_groups" => {@group.id.to_s => ["Member"]}},
        {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {@group.id.to_s => ["Member"]}}
      ]
    end

    context "pagination" do
      it "should not paginate if no type is specified" do
        # it's a synthetic result (we might a few of each type), making
        # pagination pretty tricksy. so we don't allow it
        4.times{ student_in_course(:name => "cletus") }

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=cletus&per_page=3",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'cletus', :per_page => '3'})
        json.size.should eql 3
        response.headers['Link'].should be_nil
      end

      it "should paginate users and return proper pagination headers" do
        4.times{ student_in_course(:name => "cletus") }

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=cletus&type=user&per_page=3",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'cletus', :type => 'user', :per_page => '3'})
        json.size.should eql 3
        response.headers['Link'].should eql(%{</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=2&per_page=3>; rel="next",</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=1&per_page=3>; rel="first"})

        # get the next page
        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=cletus&type=user&page=2&per_page=3",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'cletus', :type => 'user', :page => '2', :per_page => '3'})
        json.size.should eql 1
        response.headers['Link'].should eql(%{</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=1&per_page=3>; rel="prev",</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=1&per_page=3>; rel="first"})
      end

      it "should allow fetching all users iff a context is specified" do
        # for admins in particular, there may be *lots* of messageable users,
        # so we don't allow retrieval of all of them unless a context is given
        11.times{ student_in_course(:name => "cletus") }

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=cletus&type=user&per_page=-1",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'cletus', :type => 'user', :per_page => '-1'})
        json.size.should eql 10
        response.headers['Link'].should eql(%{</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=2&per_page=10>; rel="next",</api/v1/conversations/find_recipients.json?search=cletus&type=user&page=1&per_page=10>; rel="first"})

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=cletus&type=user&context=course_#{@course.id}&per_page=-1",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'cletus', :context => "course_#{@course.id}", :type => 'user', :per_page => '-1'})
        json.size.should eql 11
        response.headers['Link'].should be_nil
      end

      it "should paginate contexts and return proper pagination headers" do
        4.times{
          course_with_teacher(:active_course => true, :active_enrollment => true, :user => @user)
          @course.update_attribute(:name, "ofcourse")
        }

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=ofcourse&type=context&per_page=3",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'ofcourse', :type => 'context', :per_page => '3'})
        json.size.should eql 3
        response.headers['Link'].should eql(%{</api/v1/conversations/find_recipients.json?search=ofcourse&type=context&page=2&per_page=3>; rel="next",</api/v1/conversations/find_recipients.json?search=ofcourse&type=context&page=1&per_page=3>; rel="first"})

        # get the next page
        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=ofcourse&type=context&page=2&per_page=3",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'ofcourse', :type => 'context', :page => '2', :per_page => '3'})
        json.size.should eql 1
        response.headers['Link'].should eql(%{</api/v1/conversations/find_recipients.json?search=ofcourse&type=context&page=1&per_page=3>; rel="prev",</api/v1/conversations/find_recipients.json?search=ofcourse&type=context&page=1&per_page=3>; rel="first"})
      end

      it "should allow fetching all contexts" do
        4.times{
          course_with_teacher(:active_course => true, :active_enrollment => true, :user => @user)
          @course.update_attribute(:name, "ofcourse")
        }

        json = api_call(:get, "/api/v1/conversations/find_recipients.json?search=ofcourse&type=context&per_page=-1",
                        {:controller => 'conversations', :action => 'find_recipients', :format => 'json', :search => 'ofcourse', :type => 'context', :per_page => '-1'})
        json.size.should eql 4
        response.headers['Link'].should be_nil
      end
    end
  end

  context "conversation" do
    it "should return the conversation" do
      conversation = conversation(@bob)
      conversation.add_message("another")
      conversation.reload

      json = api_call(:get, "/api/v1/conversations/#{conversation.conversation_id}",
              { :controller => 'conversations', :action => 'show', :id => conversation.conversation_id.to_s, :format => 'json' })
      json.delete("avatar_url")
      json["participants"].each{ |p|
        p.delete("avatar_url")
      }
      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "read",
        "last_message" => "another",
        "last_message_at" => conversation.last_message_at.to_json[1, 20],
        "message_count" => 2,
        "subscribed" => true,
        "private" => true,
        "label" => nil,
        "properties" => ["last_author"],
        "audience" => [@bob.id],
        "audience_contexts" => {
          "groups" => {},
          "courses" => {@course.id.to_s => ["StudentEnrollment"]}
        },
        "participants" => [
          {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
          {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
        ],
        "messages" => [
          {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "another", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []},
          {"id" => conversation.messages.last.id, "created_at" => conversation.messages.last.created_at.to_json[1, 20], "body" => "test", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
        ],
        "submissions" => []
      })
    end

    it "should add a message to the conversation" do
      conversation = conversation(@bob)

      json = api_call(:post, "/api/v1/conversations/#{conversation.conversation_id}/add_message",
              { :controller => 'conversations', :action => 'add_message', :id => conversation.conversation_id.to_s, :format => 'json' },
              { :body => "another" })
      conversation.reload
      json.delete("avatar_url")
      json["participants"].each{ |p|
        p.delete("avatar_url")
      }
      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "read",
        "last_message" => "another",
        "last_message_at" => conversation.last_message_at.to_json[1, 20],
        "message_count" => 2, # two messages total now, though we'll only get the latest one in the response
        "subscribed" => true,
        "private" => true,
        "label" => nil,
        "properties" => ["last_author"],
        "audience" => [@bob.id],
        "audience_contexts" => {
          "groups" => {},
          "courses" => {@course.id.to_s => ["StudentEnrollment"]}
        },
        "participants" => [
          {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
          {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
        ],
        "messages" => [
          {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "another", "author_id" => @me.id, "generated" => false, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
        ]
      })
    end

    it "should add recipients to the conversation" do
      conversation = conversation(@bob, @billy)

      json = api_call(:post, "/api/v1/conversations/#{conversation.conversation_id}/add_recipients",
              { :controller => 'conversations', :action => 'add_recipients', :id => conversation.conversation_id.to_s, :format => 'json' },
              { :recipients => [@jane.id.to_s, "course_#{@course.id}"] })
      conversation.reload
      json.delete("avatar_url")
      json["participants"].each{ |p|
        p.delete("avatar_url")
      }
      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "read",
        "last_message" => "test",
        "last_message_at" => conversation.last_message_at.to_json[1, 20],
        "message_count" => 1,
        "subscribed" => true,
        "private" => false,
        "label" => nil,
        "properties" => ["last_author"],
        "audience" => [@billy.id, @bob.id, @jane.id, @joe.id, @tommy.id],
        "audience_contexts" => {
          "groups" => {},
          "courses" => {@course.id.to_s => []}
        },
        "participants" => [
          {"id" => @me.id, "name" => @me.name, "common_courses" => {}, "common_groups" => {}},
          {"id" => @billy.id, "name" => @billy.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
          {"id" => @bob.id, "name" => @bob.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
          {"id" => @jane.id, "name" => @jane.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
          {"id" => @joe.id, "name" => @joe.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}},
          {"id" => @tommy.id, "name" => @tommy.name, "common_courses" => {@course.id.to_s => ["StudentEnrollment"]}, "common_groups" => {}}
        ],
        "messages" => [
          {"id" => conversation.messages.first.id, "created_at" => conversation.messages.first.created_at.to_json[1, 20], "body" => "jane, joe, and tommy were added to the conversation by nobody@example.com", "author_id" => @me.id, "generated" => true, "media_comment" => nil, "forwarded_messages" => [], "attachments" => []}
        ]
      })
    end

    it "should update the conversation" do
      conversation = conversation(@bob, @billy)

      json = api_call(:put, "/api/v1/conversations/#{conversation.conversation_id}",
              { :controller => 'conversations', :action => 'update', :id => conversation.conversation_id.to_s, :format => 'json' },
              { :conversation => {:subscribed => false, :workflow_state => 'archived', :label => 'red'} })
      conversation.reload

      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "archived",
        "last_message" => "test",
        "last_message_at" => conversation.last_message_at.to_json[1, 20],
        "message_count" => 1,
        "subscribed" => false,
        "private" => false,
        "label" => 'red',
        "properties" => ["last_author"]
      })
    end

    it "should delete messages from the conversation" do
      conversation = conversation(@bob)
      message = conversation.add_message("another one")

      json = api_call(:post, "/api/v1/conversations/#{conversation.conversation_id}/remove_messages",
              { :controller => 'conversations', :action => 'remove_messages', :id => conversation.conversation_id.to_s, :format => 'json' },
              { :remove => [message.id] })
      conversation.reload
      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "read",
        "last_message" => "test",
        "last_message_at" => conversation.last_message_at.to_json[1, 20],
        "message_count" => 1,
        "subscribed" => true,
        "private" => true,
        "label" => nil,
        "properties" => ["last_author"]
      })
    end

    it "should delete the conversation" do
      conversation = conversation(@bob)

      json = api_call(:delete, "/api/v1/conversations/#{conversation.conversation_id}",
              { :controller => 'conversations', :action => 'destroy', :id => conversation.conversation_id.to_s, :format => 'json' })
      json.should eql({
        "id" => conversation.conversation_id,
        "workflow_state" => "read",
        "last_message" => nil,
        "last_message_at" => nil,
        "message_count" => 0,
        "subscribed" => true,
        "private" => true,
        "label" => nil,
        "properties" => []
      })
    end
  end
end

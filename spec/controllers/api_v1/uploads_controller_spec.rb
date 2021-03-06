require 'spec_helper'

describe ApiV1::UploadsController do
  before do
    make_a_typical_project

    @upload = @project.uploads.new({:asset => mock_uploader('semicolons.js', 'application/javascript', "alert('what?!')")})
    @upload.user = @user
    @upload.save!

    @page_upload = mock_file(@user, Factory.create(:page, :project_id => @project.id))
    @page = @page_upload.page
  end

  describe "#index" do
    it "shows uploads in the project" do
      login_as @user

      get :index, :project_id => @project.permalink
      response.should be_success

      data = JSON.parse(response.body)
      references = data['references'].map{|r| "#{r['id']}_#{r['type']}"}

      data['objects'].length.should == 2
      references.include?("#{@upload.user_id}_User").should == true
      references.include?("#{@upload.project_id}_Project").should == true
      references.include?("#{@page_upload.user_id}_User").should == true
      references.include?("#{@page_upload.page_id}_Page").should == true
    end

    it "shows uploads with a JSONP callback" do
      login_as @user

      get :index, :project_id => @project.permalink, :callback => 'lolCat', :format => 'js'
      response.should be_success

      response.body.split('(')[0].should == 'lolCat'
    end

    it "shows uploads as JSON when requested with the :text format" do
      login_as @user

      get :index, :project_id => @project.permalink, :format => 'text'
      response.should be_success
      response.headers['Content-Type'][/text\/plain/].should_not be_nil

      JSON.parse(response.body)['objects'].length.should == 2
    end

    it "shows uploads in all projects" do
      login_as @user

      project = Factory.create(:project)
      project.add_user(@user)
      project.uploads.new({:asset => mock_uploader('semicolons.js', 'application/javascript', "alert('what?!')")}).tap do |u|
        u.user = @user
        u.save!
      end

      get :index
      response.should be_success

      JSON.parse(response.body)['objects'].length.should == 3
    end

    it "shows uploads created by a user" do
      login_as @user

      get :index, :user_id => @user.id
      response.should be_success

      JSON.parse(response.body)['objects'].length.should == 2
    end

    it "shows no uploads created by a ficticious user" do
      login_as @user

      get :index, :user_id => -1
      response.should be_success

      JSON.parse(response.body)['objects'].length.should == 0
    end

    it "shows uploads on a page" do
      login_as @user

      get :index, :project_id => @project.permalink, :page_id => @page.id
      response.should be_success

      content = JSON.parse(response.body)['objects']
      content.length.should == 1
      content.first['id'].should == @page_upload.id
    end

    it "limits uploads" do
      login_as @user

      get :index, :project_id => @project.permalink, :count => 1
      response.should be_success

      JSON.parse(response.body)['objects'].length.should == 1
    end

    it "limits and offsets uploads" do
      login_as @user
      mock_file(@user, @page)
      @project.reload
      get :index, :project_id => @project.permalink, :since_id => @project.upload_ids[1], :count => 1
      response.should be_success
      JSON.parse(response.body)['objects'].map{|a| a['id'].to_i}.should == [@project.upload_ids[2]]
    end

    describe "private uploads" do
      before do
        @conversation = Factory.create(:conversation, :is_private => true, :user => @project.user, :project => @project)
        @upload.is_private = true
        @upload.comment = @conversation.comments.first
        @upload.save!
      end

      it "does not show private uploads belonging to objects we aren't a target of" do
        login_as @user

        get :index, :project_id => @project.permalink
        response.should be_success

        objects = JSON.parse(response.body)['objects']
        objects.map{|o| o['id']}.include?(@upload.id).should_not == true
      end

      it "shows private uploads belonging to objects we are a watcher of" do
        @conversation.add_watcher(@user)
        login_as @user

        get :index, :project_id => @project.permalink
        response.should be_success

        objects = JSON.parse(response.body)['objects']
        objects.map{|o| o['id']}.include?(@upload.id).should == true
      end
    end
  end

  describe "#show" do
    it "shows an upload with references" do
      login_as @user

      get :show, :project_id => @project.permalink, :id => @upload.id
      response.should be_success

      data = JSON.parse(response.body)
      references = data['references'].map{|r| "#{r['id']}_#{r['type']}"}

      data['id'].to_i.should == @upload.id
      references.include?("#{@upload.user_id}_User").should == true
      references.include?("#{@upload.project_id}_Project").should == true
    end

    it "does not show a private upload" do
      @conversation = Factory.create(:conversation, :is_private => true, :user => @project.user, :project => @project)
      @upload.is_private = true
      @upload.comment = @conversation.comments.first
      @upload.save!

      login_as @user

      get :show, :project_id => @project.permalink, :id => @upload.id
      response.status.should == 401
    end
  end

  describe "#create" do
    it "should allow participants to create uploads" do
      login_as @user

      post :create,
           mock_file_params.merge(:project_id => @project.permalink)
      response.should be_success

      @project.uploads(true).length.should == 3
    end

    it "should insert uploads at the top of a page" do
      login_as @user

      post :create,
           mock_file_params.merge(:project_id => @project.permalink,
             :page_id => @page.id,
             :position => {:slot => 0, :before => true})
      response.should be_success

      uid = JSON.parse(response.body)['id']
      @page.slots(true).first.rel_object.id.should == uid
    end

    it "should insert uploads at the footer of a page" do
      login_as @user

      post :create,
           mock_file_params.merge(:project_id => @project.permalink,
             :page_id => @page.id,
             :position => {:slot => -1})
      response.should be_success

      uid = JSON.parse(response.body)['id']
      @page.slots(true).last.rel_object.id.should == uid
    end

    it "should insert uploads before an existing widget" do
      login_as @user

      post :create,
           mock_file_params.merge(:project_id => @project.permalink,
             :page_id => @page.id,
             :position => {:slot => @page_upload.page_slot.id, :before => 1})
      response.should be_success

      uid = JSON.parse(response.body)['id']
      @page.uploads.find_by_id(uid).page_slot.position.should == @page_upload.page_slot.reload.position-1
    end

    it "should insert uploads after an existing widget" do
      login_as @user

      post :create,
           mock_file_params.merge(:project_id => @project.permalink,
             :page_id => @page.id,
             :position => {:slot => @page_upload.page_slot.id, :before => 0})
      response.should be_success

      uid = JSON.parse(response.body)['id']
      @page.uploads.find_by_id(uid).page_slot.position.should == @page_upload.page_slot.reload.position+1
    end

    it "should not allow observers to create uploads" do
      login_as @observer

      post :create,
           mock_file_params.merge(:project_id => @project.permalink)
      response.status.should == 401

      @project.uploads(true).length.should == 2
    end
  end

  describe "#destroy" do
    it "should allow participants to destroy an upload" do
      login_as @user

      put :destroy, :project_id => @project.permalink, :id => @upload.id
      response.should be_success

      @project.uploads(true).length.should == 1
    end

    it "should not allow observers to destroy an upload" do
      login_as @observer

      put :destroy, :project_id => @project.permalink, :id => @upload.id
      response.status.should == 401

      @project.uploads(true).length.should == 2
    end
  end
end

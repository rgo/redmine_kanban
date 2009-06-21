class KanbansController < ApplicationController
  unloadable
  helper :kanbans
  include KanbansHelper
  
  def show
    @settings = Setting.plugin_redmine_kanban
    @incoming_issues = get_incoming_issues
    @quick_issues = get_quick_issues
    @backlog_issues = get_backlog_issues(@quick_issues.values.flatten.collect(&:id))
  end

  def update
    @settings = Setting.plugin_redmine_kanban
    @from = params[:from]
    @to = params[:to]
    saved = change_issue_status(params[:issue_id], params[:from], params[:to], User.current)

    @incoming_issues = get_incoming_issues
    @backlog_issues = get_backlog_issues
    respond_to do |format|

      if saved
        format.html {
          flash[:notice] = l(:kanban_text_saved)
          redirect_to kanban_path
        }
        format.js {
          render :text => ActiveSupport::JSON.encode({
                                                       'from' => render_pane_to_js(@from),
                                                       'to' => render_pane_to_js(@to)
                                                     })
        }
      else
        format.html {
          flash[:error] = l(:kanban_text_error_saving)
          redirect_to kanban_path
        }
        format.js { 
          render({:text => ({}.to_json), :status => :bad_request})
        }
      end
    end
  end
  
  private
  def get_incoming_issues
    return Issue.visible.find(:all,
                              :limit => @settings['panes']['incoming']['limit'],
                              :order => "#{Issue.table_name}.created_on ASC",
                              :conditions => {:status_id => @settings['panes']['incoming']['status']})
  end

  def get_backlog_issues(exclude_ids=[])
    issues = Issue.visible.all(:limit => @settings['panes']['backlog']['limit'],
                               :order => "#{Issue.table_name}.created_on ASC",
                               :include => :priority,
                               :conditions => ["#{Issue.table_name}.status_id IN (?) AND #{Issue.table_name}.id NOT IN (?)", @settings['panes']['backlog']['status'], exclude_ids])

    return issues.group_by {|issue|
      issue.priority
    }.sort {|a,b|
      a[0].position <=> b[0].position # Sorted based on IssuePriority#position
    }
  end

  # TODO: similar to backlog issues
  def get_quick_issues
    issues = Issue.visible.all(:limit => @settings['panes']['quick-tasks']['limit'],
                               :order => "#{Issue.table_name}.created_on ASC",
                               :include => :priority,
                               :conditions => {:status_id => @settings['panes']['backlog']['status'], :estimated_hours => nil})

    return issues.group_by {|issue|
      issue.priority
    }.sort {|a,b|
      a[0].position <=> b[0].position # Sorted based on IssuePriority#position
    }
  end

  def change_issue_status(issue, from, to, user)
    issue = Issue.find_by_id(issue)

    if @settings['panes'][to] && @settings['panes'][to]['status']
      new_status = IssueStatus.find_by_id(@settings['panes'][to]['status'])
    end
      
    if issue && new_status
      issue.init_journal(user)
      issue.status = new_status
      return issue.save
    end
  end
end

class AdvancedSearchController < ApplicationController

  def new
    @forms = FormSection.by_order
    @page_name = t("navigation.advanced_search")
    @criteria_list = [SearchCriteria.new]
    @user = current_user
    @results = []
    prepare_params_for_limited_access_user(@user) unless can? :view_all, Child
    render :index
  end

  def index
    @page_name = t("navigation.advanced_search")
    @forms = FormSection.by_order

    @user = current_user
    prepare_params_for_limited_access_user(@user) unless can? :view_all, Child
    @criteria_list = []
    @criteria_list = (child_fields_selected?(params[:criteria_list]) ? SearchCriteria.build_from_params(params[:criteria_list]) : []) unless !params[:criteria_list]
    @criteria_list = add_search_filters(params)
    @results, @full_results = SearchService.search(params[:page] || 1, @criteria_list)
    @criteria_list = add_search_criteria_if_none(params)
  end

  def export_data
    authorize! :export, Child
    record_ids = Hash[params["selections"].to_a.sort_by { |k,v| k}].values.reverse || {} if params["all"] != "Select all records"
    record_ids = params["full_results"].split(/,/) if params["all"] == "Select all records"
    if record_ids.empty?
      raise ErrorResponse.bad_request('You must select at least one record to be exported')
    end

    children = record_ids.map { |child_id| Child.get child_id }

    RapidftrAddon::ExportTask.active.each do |addon|
      if params[:commit] == t("addons.export_task.#{addon.id}.selected")
        results = addon.new.export(children)
        encrypt_exported_files results, export_filename(children, addon)
      end
    end
  end

  def child_fields_selected? criteria_list
    if !criteria_list.nil?
      !criteria_list.first[1]["field"].blank? if !criteria_list.first[1].nil?
    end
  end

  private

  def add_search_filters params
    add_created_by_filter params
    add_updated_by_filter params
    add_created_at_filter params
    add_updated_at_filter params
    add_created_by_organisation_filter params
    @criteria_list
  end

  def add_created_by_organisation_filter params
    @criteria_list.push(SearchFilter.new({:field => "created_organisation",
                                          :value => params[:created_by_organisation_value],
                                          :index => 1,
                                          :join => "AND"})) if !self.class.nil_or_empty(params, :created_by_organisation_value)
  end

  def add_created_by_filter params
    @criteria_list.push(SearchFilter.new({:field => "created_by",
                                          :field2 => "created_by_full_name",
                                          :value => params[:created_by_value],
                                          :index => 1,
                                          :join => "AND"})) if !self.class.nil_or_empty(params, :created_by_value)
  end

  def add_updated_by_filter params
    @criteria_list.push(SearchFilter.new({:field => "last_updated_by",
                                          :field2 => "last_updated_by_full_name",
                                          :value => params[:updated_by_value],
                                          :index => 2,
                                          :join => "AND"})) if !self.class.nil_or_empty(params, :updated_by_value)
  end

  def add_created_at_filter params
    @criteria_list.push(SearchDateFilter.new({:field => "created_at",
                                              :from_value => (self.class.nil_or_empty(params, :created_at_after_value) ? "*" : "#{params[:created_at_after_value]}T00:00:00Z"),
                                              :to_value => (self.class.nil_or_empty(params, :created_at_before_value) ? "*" : "#{params[:created_at_before_value]}T00:00:00Z"),
                                              :index => 1,
                                              :join => "AND"})) if (!self.class.nil_or_empty(params, :created_at_after_value) || !self.class.nil_or_empty(params, :created_at_before_value))
  end

  def add_updated_at_filter params
    @criteria_list.push(SearchDateFilter.new({:field => "last_updated_at",
                                              :from_value => (self.class.nil_or_empty(params, :updated_at_after_value) ? "*" : "#{params[:updated_at_after_value]}T00:00:00Z"),
                                              :to_value => (self.class.nil_or_empty(params, :updated_at_before_value) ? "*" : "#{params[:updated_at_before_value]}T00:00:00Z"),
                                              :index => 2,
                                              :join => "AND"})) if (!self.class.nil_or_empty(params, :updated_at_after_value) || !self.class.nil_or_empty(params, :updated_at_before_value))
  end

  def add_search_criteria_if_none params
    @criteria_list.push(SearchCriteria.new) if !child_fields_selected?(params[:criteria_list])
    @criteria_list
  end

  def self.nil_or_empty params, key
    params[key].nil? || params[key].empty?
  end

  def prepare_params_for_limited_access_user user
    params[:created_by_value] = user.user_name
    params[:created_by] = "true"
    params[:disable_create] = "true"
  end

  def export_filename(children, export_task)
    (children.length == 1 ? children.first.short_id : current_user_name) + '_' + export_task.id.to_s + '.zip'
  end

end

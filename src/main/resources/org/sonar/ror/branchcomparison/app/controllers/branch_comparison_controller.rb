#!/usr/bin/env ruby 
require 'json'
require 'set'

METRICS = { 
  'line' => [{:name => 'ncloc', :character => 0, :type => :measure},
            {:name => 'statements', :character => 0, :type => :measure},
            {:name => 'files', :character => 0, :type => :measure},
            {:name => 'classes', :character => 0, :type => :measure},
            {:name => 'functions', :character => 0, :type => :measure},
            {:name => 'lines', :character => 0, :type => :measure}],
  'issue' => [{:name => 'blocker_violations', :character => -1,
                :type => :issue, :args => {:severity => 'BLOCKER'}},
              {:name => 'critical_violations', :character => -1,
                :type => :issue, :args => {:severity => 'CRITICAL'}},
              {:name => 'major_violations', :character => -1,
                :type => :issue, :args => {:severity => 'MAJOR'}},
              {:name => 'minor_violations', :character => -1,
                :type => :issue, :args => {:severity => 'MINOR'}},
              {:name => 'info_violations', :character => -1,
                :type => :issue, :args => {:severity => 'INFO'}},
              {:name => 'violations', :character => -1,
                :type => :issue},
              {:name => 'violations_density', :character => 1,
                :type => :issue, :args => {:highlight => 'weighted_violations',
                                            :metric => 'weighted_violations'}}],
  'comment' => [{:name => 'comment_lines', :character => 0, :type => :measure},
                {:name => 'comment_lines_density', :character => 0, :type => :measure}],
  'duplication' => [{:name => 'duplicated_lines', :character => -1, :type => :measure},
                    {:name => 'duplicated_lines_density', :character => -1,
                      :type => :measure, :args => {:highlight => 'duplicated_lines_density',
                                                    :metric => 'duplicated_lines'}},
                    {:name => 'duplicated_blocks', :character => -1, :type => :measure},
                    {:name => 'duplicated_files', :character => -1, :type => :measure}],
  'complexity' => [{:name => 'function_complexity', :character => -1, :type => :measure},
                  {:name => 'class_complexity', :character => -1, :type => :measure},
                  {:name => 'file_complexity', :character => -1, :type => :measure},
                  {:name => 'complexity', :character => -1, :type => :measure}],
}


class BranchComparisonController < ApplicationController
  helper BranchComparisonHelper
  include BranchComparisonHelper

  def initialize
    METRICS.each_pair do |key, array|
      array.each do |hash|
        metric = Metric.by_key(hash[:name])
        hash[:short_name] = metric.short_name
      end
    end
  end

  def index
    render :text => 'Branch Comparison Plugin Index Page'
  end

  # params[:id]               id/key of the base project
  # params['target']          id/key of the target project
  # params['base_version']    optional, version of the base project
  # params['target_version']  optional, version of the target project
  def result
    begin

    base_project_id = params[:id]
    target_project_id = params['target']
    @base_project = Project.by_key(base_project_id)
    @target_project = Project.by_key(target_project_id)
    unless @base_project and @target_project
      render :text => "Base project #{base_project_id} or target project #{target_project_id} not found!"
      return
    end
    @metrics = METRICS
    @metric_layout = [['line', 'comment', 'complexity'],
                      ['issue', 'duplication']]
    @base_version_list = self._get_project_versions(@base_project.id)
    @target_version_list = self._get_project_versions(@target_project.id)
    @base_version = params['base_version'] ? params['base_version'] : @base_version_list[0]
    @target_version = params['target_version'] ? params['target_version'] : @target_version_list[0]
    unless @base_version_list.include?(@base_version) and @target_version_list.include?(@target_version)
      render :text => "Version not found: base #{@base_version}, target: #{@target_version}"
    end
    @measure_data = self._get_measure_data(@base_project.id, @base_version,
                                            @target_project.id, @target_version)

    rescue => e
      render :text => e
    end
  end

  def _get_project_versions(id)
    snapshots = Snapshot.all(:conditions => ['project_id = ?', id.to_i])
    versions = snapshots.map {|snapshot| snapshot.version}
    versions = Set.new(versions).to_a
    versions = versions.sort {|a, b| a.to_f <=> b.to_f}.reverse
    return versions
  end

  def _get_measure_data(base_project_id, base_project_version, target_project_id, target_project_version)
    data = {}
    METRICS.each_pair do |category, array|
      array.each do |hash|
        metric = Metric.by_name(hash[:name])
        base_snapshot = self._get_latest_snapshot(base_project_id, base_project_version)
        base_project_measure = base_snapshot.measure(metric)
        target_snapshot = self._get_latest_snapshot(target_project_id, target_project_version)
        target_project_measure = target_snapshot.measure(metric)

        data[hash[:name]] = {'delta' => nil, 'quality' => nil}
        if base_project_measure and target_project_measure
          data[hash[:name]]['base'] = base_project_measure.formatted_value
          data[hash[:name]]['target'] = target_project_measure.formatted_value
          if base_project_measure.value.is_a?(Numeric) and target_project_measure.value.is_a?(Numeric)
            if target_project_measure.value == base_project_measure.value
              data[hash[:name]]['quality'] = 0
            else
              tmp = (target_project_measure.value - base_project_measure.value).round(1)
              tmp = tmp.to_i if tmp.to_i == tmp
              data[hash[:name]]['delta'] = tmp > 0 ? "+#{tmp}" : "#{tmp}"
              data[hash[:name]]['quality'] = (tmp > 0 ? 1 : -1) * hash[:character]
            end
          end
        else
          data[hash[:name]] = { 'base' => base_project_measure ? base_project_measure.formatted_value : nil,
                                'target' => target_project_measure ? target_project_measure.formatted_value : nil,
                                'delta' => nil,
                                'quality' => nil}
        end
      end
    end
    return data
  end

  # get latest snapshot of a specific version
  def _get_latest_snapshot(project_id, version)
    snapshot = Snapshot.first(:conditions => ['project_id = ? AND version = ?',
                                              project_id.to_i, version],
                              :order => 'created_at DESC')
    return snapshot
  end

end
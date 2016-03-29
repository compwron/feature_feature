class CreateTlosAndFeaturesAndFeatureTypes < ActiveRecord::Migration
  create_table :tlos do |t|
    t.timestamps
    t.integer :status, null: false
    t.string :required_version, null: false
  end

  create_table :features do |t|
    t.timestamps
    t.integer  :control_value, null: false
    t.uuid     :tlo_id, null: false
    t.uuid     :feature_type_id, null: false
  end
  add_index :features, [:feature_type_id]
  add_index :features, [:tlo_id]

  create_table :feature_types do |t|
    t.timestamps
    t.string   :name, null: false
    t.string   :minimum_client_version, null: false
    t.boolean  :new_tlos_on, null: false, default: false
    t.boolean  :reversible, null: false, default: false
  end
  add_index :feature_types, [:name]
end

class Tlo < ActiveRecord::Base
  include Enums::Helper
  include Concerns::Tlo::TogglingClientFeatures
  has_enumerations_for(status: Enums::Tlo::Status)
  has_many :features, as: :feature_owner
  validates :required_version, format: Semantic::Version::SemVerRegexp
end

class Enums::Tlo::Status < EnumerateIt::Base
  associate_values(
    live: 1,
    prelive: 2,
    deactivated: 3,
    test: 4,
    demo: 5
  )
end

module Concerns::Tlo::TogglingClientFeatures
  extend ActiveSupport::Concern

  included do
    after_update :update_client_features, if: :required_version_changed?
  end

  def initiate_client_features
    enable_new_tlos_on_features
  end

  def update_client_features
    FeatureType.find_each do |feature_type|
      feature = self.features.where(feature_type_id: feature_type.id).first # Bug- does not create features if none exist, only changes them
      feature.update_status if feature
    end
  end

  private

  def enable_new_tlos_on_features
     FeatureType.where(new_tlos_on: true).find_each do |feature_type|
      feature = features.where(feature_type_id: feature_type.id).new
      feature.initialize_enable
    end
  end
end

class FeatureType < ActiveRecord::Base
  # this list is used to hold any futures that cannot be safely enabled, e.g.,  by adding a Feature record
  UNSAFE_FEATURES = ['place_holder', Features::BAD_FEATURE_2]
  has_many :features, dependent: :destroy
  validates_presence_of :name, :minimum_client_version
  validates_uniqueness_of :name
  validates_format_of :minimum_client_version, with: Semantic::Version::SemVerRegexp
  after_update :update_feature_list, if: :minimum_client_version_changed?
    has_enumerations_for(status: Enums::Tlo::Status)
  scope :safe_to_enable, -> { where "name not in (?)", UNSAFE_FEATURES }

  def on_features_for_tlos
    features.where(feature_owner_type: Tlo.to_s, control_value: Enums::Feature::ControlValue::ENABLED)
  end

  def update_feature_list
    features.includes(:feature_owner).find_each do |feature|
      update_feature(feature)
    end
  end

  def update_feature(feature)
    feature_owner = feature.feature_owner
    if feature_owner.present? && feature_owner.instance_of?(Tlo)
      feature.save!
    end
  end

  def tlos_on
    Tlo.joins(:features).where(features:
      {feature_type_id: id, control_value: Enums::Feature::ControlValue::ENABLED})
  end

  def live_tlos_on
    tlos_on.live
  end

  def prelive_tlos_on
    tlos_on.prelive
  end

  def tlos_pre_enabled
    Tlo.joins(:features).where(experiments:
      {feature_type_id: id, control_value: Enums::Feature::ControlValue::PRE_ENABLED})
  end

  def live_tlos_pre_enabled
    tlos_pre_enabled.live
  end

  def prelive_tlos_pre_enabled
    tlos_pre_enabled.prelive
  end

  def tlos_on_or_pre_enabled
    Tlo.joins(:features).where(fearures: {feature_type_id: id})
  end

  def live_tlos_on_or_pre_enabled
    tlos_on_or_pre_enabled.live
  end

  def tlos_off
    Tlo.joins(tlos_join_condition).where(off_match_condition)
  end

  def live_tlos_off
    tlos_off.live
  end

  def safe_to_enable?
    !UNSAFE_FEATURES.include?(name)
  end

  def prelive_tlos_off
    tlos_off.prelive
  end

  def prelive_or_live_tlos_off
    tlos_off.prelive_or_live
  end

  private

  def tlos_join_condition
    tlos = Tlo.arel_table
    features = Feature.arel_table
    join_condition = tlos[:id].eq(features[:feature_owner_id]).and(features[:feature_type_id].eq(id))
    tlos.join(features, Arel::Nodes::OuterJoin).on(join_condition).join_sources
  end

  def off_match_condition
    Feature.arel_table[:id].eq(nil)
  end
end

class Jobs::FeatureToggle::BatchDisabler
  extend ActiveModel::Naming
  include ActiveModel::Conversion
  include ActiveModel::Validations

  attr_accessor :feature_type

  @queue = :feature_batch_disabler

  def tlos
    raise NotImplementedError "Needs to be implemented by subclass"
  end

  def count
    los.count
  end

  def save
    validate_input

    if errors.empty?
      ActiveRecord::Base.transaction do
        disable_feature_for_selected_tlos
      end
      true
    else
      false
    end
  end

  def self.perform(feature_name, criteria)
    self.new(feature_name, criteria).save
  end

  private

  def disable_feature_for_selected_tlos
    tlos.each do |tlo|
      disable_feature_for_tlo(tlo)
    end

  end

  def disable_feature_for_tlo(tlo)
    if feature = feature_for_tlo(tlo)
      LogHelper.info('job.feature_disable', tlo_id: tlo.id.to_s, feature_name: feature_type.name) do
        feature.disable!
      end
    end
  end

  def feature_for_tlo(tlo)
    tlo.features.where(feature_type_id: feature_type.id).first
  end
end

class Jobs::FeatureToggle::BatchEnabler
  extend ActiveModel::Naming
  include ActiveModel::Conversion
  include ActiveModel::Validations

  attr_accessor :feature_type

  @queue = :feature_batch_enabler

  def tlos
    raise 'Needs to be implemented by subclass'
  end

  def count
    tlos.count
  end

  def save
    validate_input

    if errors.empty?
      ActiveRecord::Base.transaction do
        enable_feature_for_selected_tlos
      end
      true
    else
      false
    end
  end

  def self.perform(feature_name, criteria)
    self.new(feature_name, criteria).save
  end

  private

  def enable_feature_for_selected_tlos
    tlos.each do |tlo|
      Mossy::publish_fragments(tlo.permalink) do
        enable_feature_for_tlo(tlo)
      end
    end
  end

  def enable_feature_for_tlo(tlo)
    LogHelper.info('job.feature_enable', tlo_id: tlo.id.to_s, feature_name: feature_type.name) do
      feature_for_tlo(tlo).initialize_enable
    end
  end

  def feature_for_tlo(tlo)
    tlo.features.where(feature_type_id: feature_type.id).first_or_initialize
  end
end

class Jobs::FeatureToggle::BatchEnablerByCount < Jobs::FeatureToggle::BatchEnabler
  attr_reader :input_count

  @queue = :feature_batch_enabler

  def initialize(feature_type_id, raw_count)
    @feature_type = FeatureType.find(feature_type_id)
    @input_count = raw_count.to_s
  end

  def tlos
    @tlos ||= random_tlos_with_version_priority
  end

  def validate_input
    unless input_count.strip.match /^\d+$/
      errors[:base] = 'Count needs to be a valid number'
    end
  end

  private

  def random_tlos_with_version_priority
    feature_type.prelive_or_live_tlos_off.order(tlo_order_clause).limit(input_count).to_a
  end

  def tlo_order_clause
    <<-ORDER
      INET_ATON(SUBSTRING_INDEX(CONCAT(`tlos`.`required_version`,'.0.0.0'),'.',4))
      >= INET_ATON(SUBSTRING_INDEX(CONCAT('#{feature_type.minimum_client_version}','.0.0.0'),'.',4)) desc, rand()
    ORDER
  end
end

class Jobs::FeatureToggle::BatchEnablerByPercentage < Jobs::FeatureToggle::BatchEnablerByCount
  attr_accessor :percentage

  @queue = :feature_batch_enabler

  def initialize(feature_type_id, percentage)
    @feature_type = FeatureType.find feature_type_id
    @percentage = percentage.to_s
  end

  def input_count
    @input_count ||= ((feature_type.prelive_or_live_tlos_off.count * percentage.to_f) / 100).round
  end

  def validate_input
    percentage_string = percentage.to_s
    unless percentage_string.strip.match(/^\d+$/) && percentage_string.to_f >= 0 && percentage_string.to_f <= 100
      errors[:base] = 'Count needs to be an integer from 0 to 100'
    end
  end
end

class BaseController < ApplicationController
  # Whatever your app uses for auth and error handling
end

class FeaturesController < BaseController
  load_and_authorize_resource

  def edit
    @features_by_type = current_features_by_type(current_tlo)
  end

  def current_features_by_type(tlo)
    {}.tap do |features_by_feature_type|
      FeatureType.safe_to_enable.each do |feature_type|
        feature = feature_for(tlo, feature_type)
        feature ||= non_persisted_enabled_feature(tlo, feature_type)
        features_by_feature_type[feature_type] = feature
      end
    end
  end

  private

  def feature_for(tlo, feature_type)
    features_by_feature_type_id(tlo, feature_type)[feature_type.id.to_s]
  end

  def features_by_feature_type_id(tlo, feature_type)
    @feature_map ||= {}.tap do |agg|
      Feature.where(feature_owner_id: tlo.id).each do |feature|
        agg[feature.feature_type_id.to_s] = feature
      end
    end
  end

  def non_persisted_enabled_feature(tlo, feature_type)
    Feature.new(
      feature_type_id: feature_type.id,
      control_value: Enums::Feature::ControlValue::ENABLED,
      feature_owner: tlo,
      feature_type: feature_type)
  end
end


  # def update_status
  #   if enabled? && !has_sufficient_version?
  #     pre_enable
  #   elsif pre_enabled? && has_sufficient_version?
  #     enable
  #   end
  # end

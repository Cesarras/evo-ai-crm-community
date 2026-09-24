# frozen_string_literal: true

# == Schema Information
#
# Table name: evo_core_integration_credentials
#
#  id            :uuid             not null, primary key
#  imported_from :string(128)
#  is_active     :boolean          default(TRUE), not null
#  kind          :string(16)       default("static"), not null
#  name          :string(255)      not null
#  owner_ref     :string(128)
#  owner_store   :string(64)
#  provider      :string(100)      not null
#  scope         :string(32)       default("account"), not null
#  value         :text
#  value_format  :string(16)       default("scalar"), not null
#  value_hint    :string(8)        default(""), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  evo_core_integration_credentials_scope_name_unique  (scope,name) UNIQUE
#  idx_evo_core_integration_credentials_kind_provider  (kind,provider)
#  idx_evo_core_integration_credentials_owner_unique   (owner_store,owner_ref) UNIQUE WHERE ((owner_store IS NOT NULL) AND (owner_ref IS NOT NULL))
#  idx_evo_core_integration_credentials_scope_active   (scope,is_active)
#
# Read-only view over `evo_core_integration_credentials`, the integration
# credential vault. Same arrangement as Ai::Credential: the core owns the table
# and every write, and the CRM reads it directly because the resolver runs in
# jobs, with no user bearer to forward over HTTP.
class Ai::IntegrationCredential < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord -- write-path validations make no sense on a read-only view of a foreign table
  self.table_name = 'evo_core_integration_credentials'

  KIND_STATIC = 'static'
  KIND_OAUTH = 'oauth'

  # Mirrors the scope chain of Ai::Credential: this service stores the scope, and
  # Ai::IntegrationCredentialResolver owns the precedence between links.
  SCOPE_INSTALLATION = 'installation'
  SCOPE_ACCOUNT = 'account'

  VALUE_FORMAT_SCALAR = 'scalar'
  VALUE_FORMAT_COMPOSITE = 'composite'

  scope :active, -> { where(is_active: true) }
  scope :for_scope, ->(scope) { where(scope: scope) }
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :static_kind, -> { where(kind: KIND_STATIC) }
  scope :oauth_kind, -> { where(kind: KIND_OAUTH) }

  def readonly?
    true
  end

  def static?
    kind == KIND_STATIC
  end

  def oauth?
    kind == KIND_OAUTH
  end
end

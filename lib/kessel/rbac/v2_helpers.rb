# frozen_string_literal: true

require_relative 'v2'

module Kessel
  module RBAC
    module V2
      include Kessel::Inventory::V1beta2

      def workspace_type
        RepresentationType.new(
          resource_type: 'workspace',
          reporter_type: 'rbac'
        )
      end

      def role_type
        RepresentationType.new(
          resource_type: 'role',
          reporter_type: 'rbac'
        )
      end

      def principal_resource(id, domain)
        ResourceReference.new(
          resource_type: 'principal',
          resource_id: "#{domain}/#{id}",
          reporter: ReporterReference.new(
            type: 'rbac'
          )
        )
      end

      def role_resource(resource_id)
        ResourceReference.new(
          resource_type: 'role',
          resource_id: resource_id,
          reporter: ReporterReference.new(
            type: 'rbac'
          )
        )
      end

      def workspace_resource(resource_id)
        ResourceReference.new(
          resource_type: 'workspace',
          resource_id: resource_id,
          reporter: ReporterReference.new(
            type: 'rbac'
          )
        )
      end

      def principal_subject(id, domain)
        SubjectReference.new(
          resource: principal_resource(id, domain)
        )
      end

      def subject(resource_ref, relation = nil)
        SubjectReference.new(
          resource: resource_ref,
          relation: relation
        )
      end
    end
  end
end

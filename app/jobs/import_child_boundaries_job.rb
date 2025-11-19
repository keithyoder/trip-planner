# app/jobs/import_child_boundaries_job.rb
class ImportChildBoundariesJob < ApplicationJob
  queue_as :default

  def perform(parent_name:, parent_level:, child_level:, leaf_depth: 1, limit: nil)
    parent = Boundary.find_by(name: parent_name, level: parent_level)

    unless parent
      Rails.logger.error "Parent boundary not found: #{parent_name} (level #{parent_level})"
      return
    end

    # Find children at specified depth
    children = Boundary.where('hierarchy ~ ?', "#{parent.hierarchy}.*{#{leaf_depth}}")

    # Filter to only leaf nodes (those without children)
    leaf_children = children.where(
      "NOT EXISTS (
        SELECT 1 FROM boundaries b2
        WHERE b2.hierarchy <@ boundaries.hierarchy
        AND b2.id != boundaries.id
      )"
    )

    # Apply limit if provided (useful for testing)
    leaf_children = leaf_children.limit(limit) if limit

    total = leaf_children.count
    Rails.logger.info "Found #{total} leaf boundaries at depth #{leaf_depth} to process"

    o = OsmBoundary.new
    success_count = 0
    error_count = 0

    leaf_children.find_each.with_index do |boundary, index|
      Rails.logger.info "[#{index + 1}/#{total}] Processing #{boundary.name} (level #{boundary.level})"

      begin
        o.fetch_and_import(
          boundary.osm_id,
          level: child_level,
          hierarchy_prefix: boundary.hierarchy
        )

        success_count += 1
        Rails.logger.info "✓ Success (#{success_count}/#{total})"
      rescue StandardError => e
        error_count += 1
        Rails.logger.error "✗ Error (#{error_count}/#{total}): #{e.message}"
      end

      # Rate limiting
      sleep(1)
    end

    Rails.logger.info '=' * 50
    Rails.logger.info 'Import Complete!'
    Rails.logger.info "Parent: #{parent_name} (level #{parent_level})"
    Rails.logger.info "Leaf Depth: #{leaf_depth}"
    Rails.logger.info "Target Child Level: #{child_level}"
    Rails.logger.info "Total: #{total}, Success: #{success_count}, Errors: #{error_count}"
    Rails.logger.info '=' * 50
  end
end

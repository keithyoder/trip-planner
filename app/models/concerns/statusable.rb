# frozen_string_literal: true

module Statusable
  extend ActiveSupport::Concern

  # The linear progression a status can advance through. `skipped` is
  # deliberately excluded — it's a side branch reachable from planning,
  # not a step in the sequence itself, so it never shows up as a "next"
  # status.
  SEQUENCE = %w[planning in_progress completed].freeze

  included do
    enum :status, { planning: 0, in_progress: 1, completed: 2, skipped: 3 }, default: :planning

    scope :current, -> { find_by(status: :in_progress) }
  end

  # @return [String, nil] the next status in sequence, or nil if there
  #   isn't one (already completed, or skipped and thus off the sequence)
  def next_status
    idx = SEQUENCE.index(status)
    return nil unless idx && idx < SEQUENCE.length - 1

    SEQUENCE[idx + 1]
  end

  def advance!
    next_s = next_status
    return false unless next_s

    update(status: next_s)
  end

  # Only planning can be skipped -- once in_progress you're committed to
  # completing it; completed and skipped are already terminal.
  def skippable?
    planning?
  end

  def skip!
    update(status: :skipped)
  end
end

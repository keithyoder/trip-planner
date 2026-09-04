# frozen_string_literal: true

# Runs on a schedule (see scheduling note below) and aggregates every
# completed EnvironmentLogAggregator bucket that hasn't been recorded yet.
# Idempotent via EnvironmentLog's unique bucket_start + the aggregator's
# own upsert, so re-running after a crash or a missed run just catches up.
class EnvironmentLogAggregationJob < ApplicationJob
  queue_as :default

  BUCKET_SECONDS = EnvironmentLogAggregator::BUCKET_SECONDS

  # Safety cap so a long gap (Sidekiq down for days, a fresh deploy with
  # months of backfill) doesn't turn one run into an unbounded loop --
  # remaining buckets just get picked up on the next scheduled run.
  MAX_BUCKETS_PER_RUN = 1440 # 24h worth at 1-minute buckets

  def perform
    bucket = next_pending_bucket
    return unless bucket

    last_complete_bucket = floor_to_bucket(Time.current - BUCKET_SECONDS)
    processed = 0

    while bucket <= last_complete_bucket && processed < MAX_BUCKETS_PER_RUN
      saved = EnvironmentLogAggregator.aggregate_bucket(bucket)
      bucket = saved ? bucket + BUCKET_SECONDS : next_bucket_with_data(bucket)
      processed += 1
    end
  end

  private

  def next_pending_bucket
    last_bucket_start = EnvironmentLog.maximum(:bucket_start)
    return last_bucket_start + BUCKET_SECONDS if last_bucket_start

    earliest = TelemetryLog.minimum(:timestamp)
    floor_to_bucket(earliest) if earliest
  end

  # Rather than plod forward one empty minute at a time through a gap
  # that could span months, jump straight to whenever the next real
  # TelemetryLog row exists.
  def next_bucket_with_data(bucket)
    next_time = TelemetryLog.where('timestamp >= ?', bucket + BUCKET_SECONDS).minimum(:timestamp)
    return bucket + BUCKET_SECONDS unless next_time

    floor_to_bucket(next_time)
  end

  def floor_to_bucket(time)
    Time.zone.at((time.to_i / BUCKET_SECONDS) * BUCKET_SECONDS)
  end
end

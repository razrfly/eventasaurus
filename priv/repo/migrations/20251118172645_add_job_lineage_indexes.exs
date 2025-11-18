defmodule EventasaurusApp.Repo.Migrations.AddJobLineageIndexes do
  use Ecto.Migration

  def change do
    # Add index on parent_job_id for fast lineage queries
    # This enables efficient queries like "find all children of job X"
    create_if_not_exists index(:job_execution_summaries, ["(results->>'parent_job_id')"],
             name: :job_execution_summaries_parent_job_id_index
           )

    # Add index on pipeline_id for batch filtering
    # This enables queries like "find all jobs in pipeline/batch X"
    create_if_not_exists index(:job_execution_summaries, ["(results->>'pipeline_id')"],
             name: :job_execution_summaries_pipeline_id_index
           )
  end
end

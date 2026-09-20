class AddAgentBotAndRequiredLabelToPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_reference :pipeline_stages, :agent_bot,
                  type: :uuid,
                  foreign_key: { to_table: :agent_bots },
                  null: true
    add_reference :pipeline_stages, :required_label,
                  type: :uuid,
                  foreign_key: { to_table: :labels },
                  null: true,
                  column: :required_label_id
    add_index :pipeline_stages, :agent_bot_id
    add_index :pipeline_stages, :required_label_id
  end
end

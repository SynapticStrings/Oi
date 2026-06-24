defmodule OiTest.DummySymbiontStep do
  @moduledoc """
  Symbiont step that reads from a model called :predicter.
  Delegates to OrchidSymbiont.call/2.
  """

  use Oi.Step, name: :predicter, symbiont?: true

  manifest(
    inputs: [:text],
    outputs: [result: :string],
    models: [:predicter]
  )

  routine text, models, _opts do
    {:ok, result} = OrchidSymbiont.call(models.predicter, {:predict, text})
    ok(result)
  end
end

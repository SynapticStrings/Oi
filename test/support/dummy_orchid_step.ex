defmodule OiTest.DummyOrchidStep do
  @moduledoc false

  defmodule DummyStep1 do
    @moduledoc false
    use Orchid.Step

    def run(%Orchid.Param{payload: inputs}, _step_options) do
      {:ok, %Orchid.Param{payload: inputs <> " -> DummyStep1"}}
    end
  end

  defmodule DummyStep2 do
    @moduledoc false
    use Orchid.Step

    def run(%Orchid.Param{payload: inputs}, _step_options) do
      {:ok, %Orchid.Param{payload: inputs <> " -> DummyStep2"}}
    end
  end

  defmodule DummyStep3 do
    @moduledoc false
    use Orchid.Step

    def run([%Orchid.Param{payload: i1}, %Orchid.Param{payload: i2}], _step_options) do
      {:ok, %Orchid.Param{payload: "DummyStep3(" <> i1 <> ", " <> i2 <> ")"}}
    end
  end

  defmodule DummyStep4 do
    @moduledoc false
    use Orchid.Step

    def run(%Orchid.Param{payload: inputs}, _step_options) do
      {:ok,
       [
         %Orchid.Param{payload: "DummyStep4(" <> inputs <> "_1)"},
         %Orchid.Param{payload: "DummyStep4(" <> inputs <> "_2)"}
       ]}
    end
  end
end

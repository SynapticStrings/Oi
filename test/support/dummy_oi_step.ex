defmodule OiTest.DummyOiStep do
  @moduledoc false

  defmodule Greet do
    use Oi.Step, name: :greet

    manifest(
      inputs: [:name],
      outputs: [greeting: :string]
    )

    routine name, _opts do
      name |> (&"Hello, #{&1}").() |> ok()
    end
  end

  defmodule Exclaim do
    use Oi.Step, name: :exclaim

    manifest(
      inputs: [:text],
      outputs: [shout: :string]
    )

    routine text, _opts do
      (text <> "!") |> ok()
    end
  end

  defmodule MultiOut do
    use Oi.Step, name: :multi

    manifest(
      inputs: [:x, :y],
      outputs: [sum: :number, product: :number]
    )

    routine [x, y], _opts do
      ok({x + y, x * y})
    end
  end

  defmodule Failer do
    use Oi.Step, name: :failer

    manifest(
      inputs: [:in],
      outputs: [out: :string]
    )

    routine _in, _opts do
      err(:intentional_failure)
    end
  end

  defmodule Predicter do
    use Oi.Step, name: :heavier, symbiont?: true

    manifest(
      inputs: [:feature],
      outputs: [prediction: :float],
      models: [:demo_model],
      heavy?: true
    )

    routine feature, models, _opts do
      {:ok, result} = OrchidSymbiont.call(models.demo_model, {:predict, feature})
      ok(result)
    end
  end
end

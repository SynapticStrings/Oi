defmodule OiTest do
  use ExUnit.Case
  doctest Oi

  test "greets the world" do
    assert Oi.hello() == :world
  end
end

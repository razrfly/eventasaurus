📊 SUMMARY TABLE - SOURCES WITH EVENTS
----------------------------------------------------------------------------------------------------
Source                Events    Overall   Time Qual   Diversity   Status
----------------------------------------------------------------------------------------------------
** (FunctionClauseError) no function clause matching in Float.round/2    
    
    The following arguments were given to Float.round/2:
    
        # 1
        48
    
        # 2
        1
    
    Attempted function clauses (showing 4 out of 4):
    
        def round(+float+, -0-) when -float == 0.0-
        def round(+float+, -0-) when -is_float(float)-
        def round(+float+, +precision+) when -is_float(float)- and +is_integer(precision)+ and +precision >= 0+ and +precision <= 15+
        def round(+float+, +precision+) when -is_float(float)-
    
    (elixir 1.18.4) lib/float.ex:349: Float.round/2
    comprehensive_time_quality_report.exs:75: anonymous fn/1 in :elixir_compiler_3.__FILE__/1
    (elixir 1.18.4) lib/enum.ex:987: Enum."-each/2-lists^foreach/1-0-"/2
    comprehensive_time_quality_report.exs:72: (file)
    (elixir 1.18.4) lib/code.ex:1525: Code.require_file/2
    (mix 1.18.4) lib/mix/tasks/run.ex:148: Mix.Tasks.Run.run/5
    (mix 1.18.4) lib/mix/tasks/run.ex:87: Mix.Tasks.Run.run/1
    (mix 1.18.4) lib/mix/task.ex:495: anonymous fn/3 in Mix.Task.run_task/5
    (mix 1.18.4) lib/mix/cli.ex:107: Mix.CLI.run_task/2
    /opt/homebrew/bin/mix:2: (file)

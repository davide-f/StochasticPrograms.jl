@testset "Stochastic Programs: Functionality" begin
    @testset "SP Constructs: $name" for (sp,res,name) in problems
        @test optimize!(sp) == :Optimal
        @test norm(optimal_decision(sp)-res.x̄) <= 1e-2
        @test abs(optimal_value(sp)-res.VRP) <= 1e-2
        @test abs(EWS(sp)-res.EWS) <= 1e-2
        @test abs(EVPI(sp)-res.EVPI) <= 1e-2
        @test abs(VSS(sp)-res.VSS) <= 1e-2
        @test abs(EV(sp)-res.EV) <= 1e-2
        @test abs(EEV(sp)-res.EEV) <= 1e-2
    end
    @testset "Inequalities: $name" for (sp,res,name) in problems
        @test EWS(sp) <= VRP(sp)
        @test VRP(sp) <= EEV(sp)
        @test VSS(sp) >= 0
        @test EVPI(sp) >= 0
        @test VSS(sp) <= EEV(sp)-EV(sp)
        @test EVPI(sp) <= EEV(sp)-EV(sp)
    end
    @testset "Deferred model creation" begin
        @test decision_length(deferred) == 0
        @test nscenarios(deferred) == 2
        @test nsubproblems(deferred) == 0
        @test optimize!(deferred) == :Optimal
        @test decision_length(deferred) == 2
        @test nscenarios(deferred) == 2
        @test nsubproblems(deferred) == 2
        @test abs(optimal_value(deferred)+855.83) <= 1e-2
    end
    @testset "Copying: $name" for (sp,res,name) in problems
        sp_copy = copy(sp)
        add_scenarios!(sp_copy, scenarios(sp))
        @test nscenarios(sp_copy) == nscenarios(sp)
        generate!(sp_copy)
        @test nsubproblems(sp_copy) == nsubproblems(sp)
        @test optimize!(sp_copy) == :Optimal
        optimize!(sp)
        @test norm(optimal_decision(sp_copy)-optimal_decision(sp)) <= 1e-2
        @test abs(optimal_value(sp_copy)-optimal_value(sp)) <= 1e-2
        @test abs(EWS(sp_copy)-EWS(sp)) <= 1e-2
        @test abs(EVPI(sp_copy)-EVPI(sp)) <= 1e-2
        @test abs(VSS(sp_copy)-VSS(sp)) <= 1e-2
        @test abs(EV(sp_copy)-EV(sp)) <= 1e-2
        @test abs(EEV(sp_copy)-EEV(sp)) <= 1e-2
    end
    @testset "Sampling" begin
        sampled_sp = sample(simple_model, sampler, 100, solver=GLPKSolverLP())
        @test nscenarios(sampled_sp) == 100
        @test nsubproblems(sampled_sp) == 100
        @test abs(stage_probability(sampled_sp)-1.0) <= 1e-6
        sample!(sampled_sp, sampler, 100)
        @test nscenarios(sampled_sp) == 200
        @test nsubproblems(sampled_sp) == 200
        @test abs(stage_probability(sampled_sp)-1.0) <= 1e-6
    end
    @testset "Confidence intervals" begin
        glpk = GLPKSolverLP()
        CI = confidence_interval(simple_model, sampler, solver = glpk, N = 200, log = false)
        @test lower(CI) <= upper(CI)
        sol = optimize!(simple_model, sampler, solver = glpk, confidence = 0.95, tol = 1e-1, log = false)
        @test lower(confidence_interval(sol)) <= upper(confidence_interval(sol))
    end
end

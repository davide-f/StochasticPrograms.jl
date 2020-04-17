# API (Two-stage) #
# ========================== #
"""
    instantiate(stochasticmodel::TwoStageStochasticProgram,
                scenarios::Vector{<:AbstractScenario};
                optimizer = nothing;
                procs::Vector{Int} = workers(),
                float_type::Type{<:AbstractFloat} = Float64,
                defer::Bool = false,
                kw...)

Instantiate a new two-stage stochastic program using the model definition stored in the two-stage `stochasticmodel`, and the given collection of `scenarios`.
"""
function instantiate(sm::TwoStageStochasticProgram,
                     scenarios::Vector{<:AbstractScenario};
                     optimizer = nothing,
                     procs::Vector{Int} = workers(),
                     float_type::Type{<:AbstractFloat} = Float64,
                     defer::Bool = false,
                     kw...)
    sp = StochasticProgram(parameters(sm.parameters[1]; kw...),
                           parameters(sm.parameters[2]; kw...),
                           float_type,
                           scenarios,
                           procs,
                           optimizer)
    # Generate model recipes
    sm.generator(sp)
    # Generate decision variables using model recipes
    generate_decision_variables!(sp)
    # Initialize if not deferred
    if !defer
        initialize!(sp)
    end
    return sp
end
"""
    instantiate(stochasticmodel::TwoStageStochasticProgram;
                optimizer = nothing,
                scenariotype::Type{S} = Scenario,
                procs::Vector{Int} = workers(),
                float_type::Type{<:AbstractFloat} = Float64,
                defer::Bool = false,
                kw...) where S <: AbstractScenario

Instantiate a deferred two-stage stochastic program using the model definition stored in the two-stage `stochasticmodel` over the scenario type `S`.
"""
function instantiate(sm::TwoStageStochasticProgram;
                     optimizer = nothing,
                     scenariotype::Type{S} = Scenario,
                     procs::Vector{Int} = workers(),
                     float_type::Type{<:AbstractFloat} = Float64,
                     kw...) where S <: AbstractScenario
    sp = StochasticProgram(parameters(sm.parameters[1]; kw...),
                           parameters(sm.parameters[2]; kw...),
                           float_type,
                           scenariotype,
                           procs,
                           optimizer)
    # Generate model recipes
    sm.generator(sp)
    # Generate decision variables using model recipes
    generate_decision_variables!(sp)
    return sp
end
"""
    instantiate(stochasticmodel::StochasticModel,
                scenarios::Vector{<:AbstractScenario};
                optimizer = nothing,
                procs::Vector{Int} = workers(),
                float_type::Type{<:AbstractFloat} = Float64,
                defer::Bool = false,
                kw...)

Instantiate a new stochastic program using the model definition stored in `stochasticmodel`, and the given collection of `scenarios`.
"""
function instantiate(sm::StochasticModel{N},
                     scenarios::NTuple{M,Vector{<:AbstractScenario}};
                     optimizer = nothing,
                     procs::Vector{Int} = workers(),
                     float_type::Type{<:AbstractFloat} = Float64,
                     defer::Bool = false,
                     kw...) where {N,M}
    M == N - 1 || error("Inconsistent number of stages $N and number of scenario types $M")
    params = ntuple(Val(N)) do i
        parameters(sm.parameters[i]; kw...)
    end
    sp = StochasticProgram(float_type,
                           params,
                           scenarios,
                           procs,
                           optimizer)
    # Generate model recipes
    sm.generator(sp)
    # Generate decision variables using model recipes
    generate_decision_variables!(sp)
    # Initialize model if not deferred
    if !defer
        initialize!(sp)
    end
    return sp
end
"""
    sample(stochasticmodel::StochasticModel,
           sampler::AbstractSampler,
           n::Integer;
           optimizer = nothing,
           procs::Vector{Int} = workers(),
           float_type::Type{<:AbstractFloat} = Float64,
           defer::Bool = false,
           kw...)

Generate a sampled instance of size `n` using the model stored in the two-stage `stochasticmodel`, and the provided `sampler`.

Optionally, a capable `optimizer` can be supplied to `sample`. Otherwise, any previously set solver will be used.

See also: [`sample!`](@ref)
"""
function sample(sm::TwoStageStochasticProgram,
                sampler::AbstractSampler{S},
                n::Integer;
                optimizer = nothing,
                procs::Vector{Int} = workers(),
                float_type::Type{<:AbstractFloat} = Float64,
                defer::Bool = false,
                kw...) where S <: AbstractScenario
    # Create new stochastic program instance
    sp = StochasticProgram(parameters(sm.parameters[1]; kw...),
                           parameters(sm.parameters[2]; kw...),
                           float_type,
                           S,
                           procs,
                           optimizer)
    # Generate model recipes
    sm.generator(sp)
    # Generate decision variables using model recipes
    generate_decision_variables!(sp)
    # Sample n scenarios
    add_scenarios!(sp, n) do
        return sample(sampler, 1/n)
    end
    # Initialize model if not deferred
    if !defer
        initialize!(sp)
    end
    # Return the sample instance
    return sp
end
function sample(sm::TwoStageStochasticProgram,
                sampler::AbstractSampler{S},
                solution::StochasticSolution;
                optimizer = nothing,
                procs::Vector{Int} = workers(),
                float_type::AbstractFloat = Float64,
                defer::Bool = false,
                kw...) where S <: AbstractScenario
    if optimizer == nothing
        error("Cannot generate sample from stochastic solution without an optimizer.")
    end
    n = 16
    CI = confidence_interval(solution)
    α = 1 - confidence(CI)
    while !(confidence_interval(sm, sampler, optimizer; N = n, M = M, confidence = 1-α) ⊆ CI)
        n = n * 2
    end
    return sample(sm, sampler, n, optimizer; float_type = float_type, procs = procs, defer = defer)
end
"""
    optimize!(stochasticprogram::StochasticProgram)

Optimize the `stochasticprogram` in expectation. If an optimizer has not been set yet (see [`set_optimizer!`](@ref)), a `NoOptimizer` error is thrown.

## Examples

The following solves the stochastic program `sp` using the L-shaped algorithm.

```julia
using LShapedSolvers
using GLPKMathProgInterface

set_optimizer!(sp, LShapedOptimizer)
optimize!(sp);

# output

L-Shaped Gap  Time: 0:00:01 (4 iterations)
  Objective:       -855.8333333333339
  Gap:             0.0
  Number of cuts:  7
:Optimal
```

The following solves the stochastic program `sp` using GLPK on the extended form.

```julia
using GLPKMathProgInterface

set_optimizer!(sp, GLPK.Optimizer)
optimize!(sp)

:Optimal
```

See also: [`VRP`](@ref)
"""
function JuMP.optimize!(stochasticprogram::TwoStageStochasticProgram; kwargs...)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    # Ensure stochastic program has been initialized at this point
    if !initialized(stochasticprogram)
        initialize!(stochasticprogram)
    end
    # Switch on solver type
    return _optimize!(stochasticprogram, provided_optimizer(stochasticprogram); kwargs...)
end
function _optimize!(stochasticprogram::TwoStageStochasticProgram, ::OptimizerProvided; kwargs...)
    # MOI optimizer. Fallback to solving DEP, relying on JuMP.
    dep = DEP(stochasticprogram)
    optimize!(dep)
    status = termination_status(dep)
    return status
end
function _optimize!(stochasticprogram::TwoStageStochasticProgram, ::StructuredOptimizerProvided; kwargs...)
    # Ensure stochastic program has been generated at this point
    if deferred(stochasticprogram)
        generate!(stochasticprogram)
    end
    # Structure-exploiting optimizer.
    optimize_structured!(optimizer(stochasticprogram))
    return termination_status(optimizer(stochasticprogram))
end
function JuMP.termination_status(stochasticprogram::StochasticProgram)
    return _termination_status(stochasticprogram, provided_optimizer(stochasticprogram))
end
function _termination_status(stochasticprogram::StochasticProgram, ::Union{NoOptimizerProvided, UnrecognizedOptimizerProvided})
    return MOI.OPTIMIZE_NOT_CALLED
end
function _termination_status(stochasticprogram::StochasticProgram, ::OptimizerProvided)
    return termination_status(DEP(stochasticprogram))
end
function _termination_status(stochasticprogram::StochasticProgram, ::Union{StructuredOptimizerProvided, SampledOptimizerProvided})
    return termination_status(optimizer(stochasticprogram))
end
"""
    optimal_decision(stochasticprogram::StochasticProgram)

Return the optimal first stage decision of `stochasticprogram`, after a call to `optimize!(stochasticprogram)`.
"""
function optimal_decision(stochasticprogram::TwoStageStochasticProgram)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    # Dispatch on provided optimizer
    return _optimal_decision(stochasticprogram, provided_optimizer(stochasticprogram))
end
function _optimal_decision(stochasticprogram::TwoStageStochasticProgram, ::OptimizerProvided)
    dep = DEP(stochasticprogram)
    status = termination_status(dep)
    if status != MOI.OPTIMAL
        if status == MOI.OPTIMIZE_NOT_CALLED
            throw(OptimizeNotCalled())
        elseif status == MOI.INFEASIBLE
            @warn "Stochastic program is infeasible"
        elseif status == MOI.DUAL_INFEASIBLE
            @warn "Stochastic program is unbounded"
        else
            error("Stochastic program could not be solved, returned status: $status")
        end
    end
    decision = extract_decision_variables(dep, decision_variables(stochasticprogram, 1))
    return decision
end
"""
    optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram, i::Integer)

Return the optimal recourse decision of `stochasticprogram` corresponding to the `i`th scenario, after a call to `optimize!(stochasticprogram)`.
"""
function optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram, i::Integer)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    # Dispatch on provided optimizer
    return _optimal_recourse_decision(stochasticprogram, i, provided_optimizer(stochasticprogram))
end
function _optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram, i::Integer, ::OptimizerProvided)
    dep = DEP(stochasticprogram)
    status = termination_status(dep)
    if status != MOI.OPTIMAL
        if status == MOI.OPTIMIZE_NOT_CALLED
            throw(OptimizeNotCalled())
        elseif status == MOI.INFEASIBLE
            @warn "Stochastic program is infeasible"
        elseif status == MOI.DUAL_INFEASIBLE
            @warn "Stochastic program is unbounded"
        else
            error("Stochastic program model could not be solved, returned status: $status")
        end
    end
    temp = copy(decision_variables(stochasticprogram, 2))
    for (i,dvar) in enumerate(decision_names(temp))
        temp.names[i] = add_subscript(dvar, i)
    end
    decision = extract_decision_variables(dep, temp)
    decision.names .= decision_names(decision_variables(stochasticprogram, 2))
    return decision
end
"""
    optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram,
                              decision::Union{AbstractVector, DecisionVariables},
                              scenario::AbstractScenario)

Return the optimal recourse decision of `stochasticprogram` corresponding to the given `scenario`, after taking the given `decision`. The supplied `decision` must be of type `AbstractVector` or `DecisionVariables`, and must match the defined decision variables in `stochasticprogram`. If an optimizer has not been set yet (see [`set_optimizer!`](@ref)), a `NoOptimizer` error is thrown.
"""
function optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram,
                                   decision::DecisionVariables,
                                   scenario::AbstractScenario)
    # Sanity checks on given decision vector
    decision_names(decision_variables(stochasticprogram)) == decision_names(decision) || error("Given decision does not match decision variables in stochastic program.")
    return optimal_recourse_decision(stochasticprogram, decisions(decision), scenario)
end
function optimal_recourse_decision(stochasticprogram::TwoStageStochasticProgram,
                                   decision::AbstractVector,
                                   scenario::AbstractScenario)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    # Sanity checks on given decision vector
    length(decision) == decision_length(stochasticprogram) || error("Incorrect length of given decision vector, has ", length(decision), " should be ", decision_length(stochasticprogram))
    all(.!(isnan.(decision))) || error("Given decision vector has NaN elements")
    # Generate and solve outcome model
    outcome = outcome_model(stochasticprogram, decision, scenario; optimizer = moi_optimizer(stochasticprogram))
    optimize!(outcome)
    status = termination_status(outcome)
    if status != MOI.OPTIMAL
        if status == MOI.OPTIMIZE_NOT_CALLED
            throw(OptimizeNotCalled())
        elseif status == MOI.INFEASIBLE
            @warn "Outcome is infeasible"
        elseif status == MOI.DUAL_INFEASIBLE
            @warn "Outcome is unbounded"
        else
            error("Outcome model could not be solved, returned status: $status")
        end
    end
    decision = extract_decision_variables(outcome, decision_variables(stochasticprogram, 2))
    return decision
end
"""
    optimal_value(stochasticprogram::StochasticProgram)

Return the optimal value of `stochasticprogram`, after a call to `optimize!(stochasticprogram)`.
"""
function optimal_value(stochasticprogram::StochasticProgram)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    return _optimal_value(stochasticprogram, provided_optimizer(stochasticprogram))
end
function _optimal_value(stochasticprogram::StochasticProgram, ::OptimizerProvided)
    dep = DEP(stochasticprogram)
    status = termination_status(dep)
    if status == MOI.OPTIMIZE_NOT_CALLED
        throw(OptimizeNotCalled())
    elseif status == MOI.INFEASIBLE
        @warn "Stochastic program is infeasible"
        return objective_sense(outcome) == MOI.MAX_SENSE ? -Inf : Inf
    elseif status == MOI.DUAL_INFEASIBLE
        @warn "Stochastic program is unbounded"
        return objective_sense(outcome) == MOI.MAX_SENSE ? Inf : -Inf
    else
        error("Stochastic program could not be solved, returned status: $status")
    end
    return objective_value(dep)
end
"""
    optimize!(stochasticmodel::StochasticModel, sampler::AbstractSampler; confidence::AbstractFloat = 0.95, kwargs...)

Approximately optimize the `stochasticmodel` using when the underlying scenario distribution is inferred by `sampler` and return a `StochasticSolution` with the given `confidence` level. If an optimizer has not been set yet (see [`set_optimizer!`](@ref)), a `NoOptimizer` error is thrown.

See also: [`StochasticSolution`](@ref)
"""
function JuMP.optimize!(stochasticmodel::StochasticModel,
                        sampler::AbstractSampler;
                        confidence::AbstractFloat = 0.95,
                        kwargs...)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(provided_optimizer(stochasticmodel))
    # Switch on solver type
    return _optimize!(stochasticmodel, sampler, confidence, provided_optimizer(stochasticmodel); kwargs...)
end
function _optimize!(stochasticmodel::StochasticModel,
                    sampler::AbstractSampler,
                    confidence::AbstractFloat,
                    ::Union{OptimizerProvided, StructuredOptimizerProvided};
                    kwargs...)
    # Default to SAA algorithm if standard optimizers have been provided
    stochasticmodel.optimizer.optimizer = SAA()
    return optimize_sampled!(optimizer(stochasticmodel), stochasticmodel, sampler, confidence; kwargs...)
end
function _optimize!(stochasticmodel::StochasticModel,
                    sampler::AbstractSampler,
                    confidence::AbstractFloat,
                    ::SampledOptimizerProvided;
                    kwargs...)
    return optimize_sampled!(optimizer(stochasticmodel), stochasticmodel, sampler, confidence; kwargs...)
end
function JuMP.termination_status(stochasticmodel::StochasticModel)
    return _termination_status(stochasticmodel, provided_optimizer(stochasticmodel))
end
function _termination_status(stochasticmodel::StochasticModel, ::Union{NoOptimizerProvided, UnrecognizedOptimizerProvided})
    return MOI.OPTIMIZE_NOT_CALLED
end
function _termination_status(stochasticmodel::StochasticModel, ::Union{OptimizerProvided, StructuredOptimizerProvided, SampledOptimizerProvided})
    return termination_status(optimizer(stochasticmodel))
end
"""
    optimal_decision(stochasticmodel::StochasticModel)

Return the optimal first stage decision of `stochasticmodel`, after a call to `optimize!(stochasticmodel)`.
"""
function optimal_decision(stochasticmodel::StochasticModel)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(provided_optimizer(stochasticmodel))
    return optimal_decision(optimizer(stochasticmodel))
end
"""
    optimal_value(stochasticmodel::StochasticModel)

Return the optimal value of `stochasticmodel`, after a call to `optimize!(stochasticmodel)`.
"""
function optimal_value(stochasticmodel::StochasticModel)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(provided_optimizer(stochasticmodel))
    return optimal_value(optimizer(stochasticmodel))
end
"""
    stage_parameters(stochasticprogram::StochasticProgram, s::Integer)

Return the parameters at stage `s` in `stochasticprogram`.
"""
function stage_parameters(stochasticprogram::StochasticProgram{N}, s::Integer) where N
    1 <= s <= N || error("Stage $s not in range 1 to $N.")
    return stochasticprogram.stages[s].parameters
end
"""
    decision_variables(stochasticprogram::StochasticProgram)

Return the decision variables of stage `s` in `stochasticprogram`. Defaults to the second stage.
"""
function decision_variables(stochasticprogram::StochasticProgram{N}, s::Integer) where N
    1 <= s <= N || error("Stage $s not in range 1 to $(N - 1).")
    return decision_variables(structure(stochasticprogram), 2)
end
"""
    decision_variables(stochasticprogram::TwoStageStochasticProgram)

Return the first-stage decision variables of the two-stage `stochasticprogram`.
"""
function decision_variables(stochasticprogram::TwoStageStochasticProgram)
    return decision_variables(stochasticprogram, 1)
end
"""
    recourse_variables(stochasticprogram::TwoStageStochasticProgram)

Return the second-stage recourse variables of the two-stage `stochasticprogram`.
"""
function recourse_variables(stochasticprogram::TwoStageStochasticProgram)
    return decision_variables(stochasticprogram, 2)
end
"""
    structure(stochasticprogram::StochasticProgram)

Return the underlying structure of the `stochasticprogram`.
"""
function structure(stochasticprogram::StochasticProgram)
    return stochasticprogram.structure
end
"""
    decision_length(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the length of the decision at stage `s` in the `stochasticprogram`.
"""
function decision_length(stochasticprogram::StochasticProgram{N}, s::Integer) where N
    1 <= s <= N || error("Stage $s not in range 2 to $N.")
    return ndecisions(decision_variables(stochasticprogram, s))
end
"""
    decision_length(stochasticprogram::TwoStageStochasticProgram)

Return the length of the first-stage decision of `stochasticprogram`.
"""
function decision_length(stochasticprogram::TwoStageStochasticProgram)
    return decision_length(stochasticprogram, 1)
end
"""
    first_stage(stochasticprogram::StochasticProgram)

Return the first stage of `stochasticprogram`.
"""
function first_stage(stochasticprogram::StochasticProgram; optimizer = nothing)
    return first_stage(stochasticprogram, structure(stochasticprogram); optimizer = optimizer)
end
function first_stage(stochasticprogram::StochasticProgram, ::AbstractStochasticStructure; optimizer = nothing)
    # Return possibly cached model
    cache = problemcache(stochasticprogram)
    if haskey(cache, :stage_1)
        stage_one = cache[:stage_1]
        optimizer != nothing && set_optimizer(stage_one, optimizer)
        return stage_one
    end
    # Check that the required generators have been defined
    has_generator(stochasticprogram, :stage_1) || error("First-stage problem not defined in stochastic program. Consider @stage 1.")
    # Generate and cache first stage
    generate_stage_one!(stochasticprogram)
    stage_one = cache[:stage_1]
    optimizer != nothing && set_optimizer(stage_one, optimizer)
    return stage_one
end
"""
    first_stage_nconstraints(stochasticprogram::StochasticProgram)

Return the number of constraints in the the first stage of `stochasticprogram`.
"""
function first_stage_nconstraints(stochasticprogram::StochasticProgram)
    !haskey(stochasticprogram.problemcache, :stage_1) && return 0
    first_stage = get_stage_one(stochasticprogram)
    return num_constraints(first_stage)
end
"""
    first_stage_dims(stochasticprogram::StochasticProgram)

Return a the number of variables and the number of constraints in the the first stage of `stochasticprogram` as a tuple.
"""
function first_stage_dims(stochasticprogram::StochasticProgram)
    !haskey(stochasticprogram.problemcache, :stage_1) && return 0, 0
    first_stage = get_stage_one(stochasticprogram)
    return num_constraints(first_stage), num_variables(first_stage)
end
"""
    scenario(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)

Return the `i`th scenario of stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function scenario(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)
    return scenario(structure(stochasticprogram), i, s)
end
"""
    scenarios(stochasticprogram::StochasticProgram, s::Integer = 2)

Return an array of all scenarios of the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function scenarios(stochasticprogram::StochasticProgram, s::Integer = 2)
    return scenarios(structure(stochasticprogram), s)
end
"""
    expected(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the exected scenario of all scenarios of the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function expected(stochasticprogram::StochasticProgram, s::Integer = 2)
    return expected(structure(stochasticprogram), s)
end
"""
    scenariotype(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the type of the scenario structure associated with `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function scenariotype(stochasticprogram::StochasticProgram, s::Integer = 2)
    return scenariotype(structure(stochasticprogram), s)
end
"""
    probability(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)

Return the probability of scenario `i`th scenario in the `stochasticprogram` at stage `s` occuring. Defaults to the second stage.
"""
function probability(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)
    return probability(structure(stochasticprogram), i, s))
end
"""
    stage_probability(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the probability of any scenario in the `stochasticprogram` at stage `s` occuring. A well defined model should return 1. Defaults to the second stage.
"""
function stage_probability(stochasticprogram::StochasticProgram, s::Integer = 2)
    return probability(structure(stochasticprogram), s)
end
"""
    has_generator(stochasticprogram::StochasticProgram, key::Symbol)

Return true if a problem generator with `key` exists in `stochasticprogram`.
"""
function has_generator(stochasticprogram::StochasticProgram, key::Symbol)
    return haskey(stochasticprogram.generator, key)
end
"""
    generator(stochasticprogram::StochasticProgram, key::Symbol)

Return the problem generator associated with `key` in `stochasticprogram`.
"""
function generator(stochasticprogram::StochasticProgram, key::Symbol)
    return stochasticprogram.generator[key]
end
"""
    subproblem(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)

Return the `i`th subproblem of the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function subproblem(stochasticprogram::StochasticProgram, i::Integer, s::Integer = 2)
    return subproblem(structure(stochasticprogram), s, i)
end
"""
    subproblems(stochasticprogram::StochasticProgram, s::Integer = 2)

Return an array of all subproblems of the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function subproblems(stochasticprogram::StochasticProgram, s::Integer = 2)
    return subproblems(structure(stochasticprogram), s)
end
"""
    nsubproblems(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the number of subproblems in the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function nsubproblems(stochasticprogram::StochasticProgram, s::Integer = 2)
    s == 1 && return 0
    return nsubproblems(structure(stochasticprogram), s)
end
"""
    nscenarios(stochasticprogram::StochasticProgram, s::Integer = 2)

Return the number of scenarios in the `stochasticprogram` at stage `s`. Defaults to the second stage.
"""
function nscenarios(stochasticprogram::StochasticProgram, s::Integer = 2)
    s == 1 && return 0
    return nscenarios(structure(stochasticprogram), s)
end
"""
    nstages(stochasticprogram::StochasticProgram)

Return the number of stages in `stochasticprogram`.
"""
nstages(::StochasticProgram{N}) where N = N
"""
    distributed(stochasticprogram::StochasticProgram, s::Integer = 2)

Return true if the `stochasticprogram` is memory distributed at stage `s`. Defaults to the second stage.
"""
distributed(stochasticprogram::StochasticProgram, s::Integer = 2) = distributed(scenarioproblems(stochasticprogram, s))
"""
    deferred(stochasticprogram::StochasticProgram)

Return true if `stochasticprogram` is not fully generated.
"""
deferred(stochasticprogram::StochasticProgram) = deferred(structure(stochasticprogram))
"""
    optimizer_constructor(stochasticmodel::StochasticModel)

Return any optimizer constructor supplied to the `stochasticmodel`.
"""
function optimizer_constructor(stochasticmodel::StochasticModel)
    return stochasticmodel.optimizer.optimizer_constructor
end
"""
    optimizer_constructor(stochasticprogram::StochasticProgram)

Return any optimizer constructor supplied to the `stochasticprogram`.
"""
function optimizer_constructor(stochasticprogram::StochasticProgram)
    return stochasticprogram.optimizer.optimizer_constructor
end
"""
    optimizer_name(stochasticmodel::StochasticModel)

Return the currently provided optimizer type of `stochasticmodel`.
"""
function optimizer_name(stochasticmodel::StochasticModel)
    return optimizer_name(optimizer(stochasticmodel))
end
"""
    optimizer_name(stochasticprogram::StochasticProgram)

Return the currently provided optimizer type of `stochasticprogram`.
"""
function optimizer_name(stochasticprogram::StochasticProgram)
    deferred(stochasticprogram) && return "Uninitialized"
    return optimizer_name(optimizer(stochasticprogram))
end
function optimizer_name(optimizer::MOI.AbstractOptimizer)
    return JuMP._try_get_solver_name(optimizer)
end
"""
    moi_optimizer(stochasticmodel::StochasticModel)

Return a MOI capable optimizer using the currently provided optimizer of `stochasticmodel`.
"""
function moi_optimizer(stochasticmodel::StochasticModel)
    return moi_optimizer(stochasticmodel.optimizer)
end
"""
    moi_optimizer(stochasticprogram::StochasticProgram)

Return a MOI capable optimizer using the currently provided optimizer of `stochasticprogram`.
"""
function moi_optimizer(stochasticprogram::StochasticProgram)
    return moi_optimizer(stochasticprogram.optimizer)
end
"""
    optimizer(stochasticprogram::StochasticProgram)

Return, if any, the optimizer attached to `stochasticprogram`.
"""
function optimizer(stochasticprogram::StochasticProgram)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(stochasticprogram.optimizer)
    return stochasticprogram.optimizer.optimizer
end
"""
    optimizer(stochasticmodel::StochasticModel)

Return, if any, the optimizer attached to `stochasticmodel`.
"""
function optimizer(stochasticmodel::StochasticModel)
    # Throw NoOptimizer error if no recognized optimizer has been provided
    _check_provided_optimizer(provided_optimizer(stochasticmodel))
    return stochasticmodel.optimizer.optimizer
end
# ========================== #

# Setters
# ========================== #
"""
    set_optimizer!(stochasticmodel::StochasticModel, optimizer)

Set the optimizer of the `stochasticmodel`.
"""
function set_optimizer!(stochasticmodel::StochasticModel, optimizer)
    stochasticmodel.optimizer.optimizer_constructor = optimizer
    return nothing
end
"""
    set_optimizer!(stochasticprogram::StochasticProgram, optimizer)

Set the optimizer of the `stochasticprogram`.
"""
function set_optimizer!(stochasticprogram::StochasticProgram, optimizer; defer::Bool = false)
    set_optimizer!(stochasticprogram.optimizer, optimizer)
    if !defer
        generate!(stochasticprogram)
    end
    return nothing
end
"""
    add_scenario!(stochasticprogram::StochasticProgram, scenario::AbstractScenario, stage::Integer = 2)

Store the second stage `scenario` in the `stochasticprogram` at `stage`. Defaults to the second stage.

If the `stochasticprogram` is distributed, the scenario will be defined on the node that currently has the fewest scenarios.
"""
function add_scenario!(stochasticprogram::StochasticProgram, scenario::AbstractScenario, stage::Integer = 2)
    add_scenario!(structure(stochasticprogram), stage, scenario)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_worker_scenario!(stochasticprogram::StochasticProgram, scenario::AbstractScenario, w::Integer, stage::Integer = 2)

Store the second stage `scenario` in worker node `w` of the `stochasticprogram` at `stage`. Defaults to the second stage.
"""
function add_worker_scenario!(stochasticprogram::StochasticProgram, scenario::AbstractScenario, w::Integer, stage::Integer = 2)
    add_scenario!(structure(stochasticprogram), stage, scenario, w)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_scenario!(scenariogenerator::Function, stochasticprogram::StochasticProgram, stage::Integer = 2)

Store the second stage scenario returned by `scenariogenerator` in the second stage of the `stochasticprogram`. Defaults to the second stage. If the `stochasticprogram` is distributed, the scenario will be defined on the node that currently has the fewest scenarios.
"""
function add_scenario!(scenariogenerator::Function, stochasticprogram::StochasticProgram, stage::Integer = 2)
    add_scenario!(scenariogenerator, structure(stochasticprogram), stage)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_worker_scenario!(scenariogenerator::Function, stochasticprogram::StochasticProgram, w::Integer, stage::Integer = 2)

Store the second stage scenario returned by `scenariogenerator` in worker node `w` of the `stochasticprogram` at `stage`. Defaults to the second stage.
"""
function add_worker_scenario!(scenariogenerator::Function, stochasticprogram::StochasticProgram, w::Integer, stage::Integer = 2)
    add_scenario!(scenariogenerator, structure(stochasticprogram), stage, w)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_scenarios!(stochasticprogram::StochasticProgram, scenarios::Vector{<:AbstractScenario}, stage::Integer = 2)

Store the collection of second stage `scenarios` in the `stochasticprogram` at `stage`. Defaults to the second stage. If the `stochasticprogram` is distributed, scenarios will be distributed evenly across workers.
"""
function add_scenarios!(stochasticprogram::StochasticProgram, scenarios::Vector{<:AbstractScenario}, stage::Integer = 2)
    add_scenarios!(structure(stochasticprogram), stage, scenarios)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_worker_scenarios!(stochasticprogram::StochasticProgram, scenarios::Vector{<:AbstractScenario}, w::Integer, stage::Integer = 2; defer::Bool = false)

Store the collection of second stage `scenarios` in in worker node `w` of the `stochasticprogram` at `stage`. Defaults to the second stage.
"""
function add_worker_scenarios!(stochasticprogram::StochasticProgram, scenarios::Vector{<:AbstractScenario}, w::Integer, stage::Integer = 2)
    add_scenarios!(structure(stochasticprogram), stage, scenarios, w)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_scenarios!(scenariogenerator::Function, stochasticprogram::StochasticProgram, n::Integer, stage::Integer = 2; defer::Bool = false)

Generate `n` second-stage scenarios using `scenariogenerator`and store in the `stochasticprogram` at `stage`. Defaults to the second stage. If the `stochasticprogram` is distributed, scenarios will be distributed evenly across workers.
"""
function add_scenarios!(scenariogenerator::Function, stochasticprogram::StochasticProgram, n::Integer, stage::Integer = 2)
    add_scenarios!(scenariogenerator, structure(stochasticprogram), stage, n)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    add_worker_scenarios!(scenariogenerator::Function, stochasticprogram::StochasticProgram, n::Integer, w::Integer, stage::Integer = 2; defer::Bool = false)

Generate `n` second-stage scenarios using `scenariogenerator`and store them in worker node `w` of the `stochasticprogram` at `stage`. Defaults to the second stage.
"""
function add_worker_scenarios!(scenariogenerator::Function, stochasticprogram::StochasticProgram, n::Integer, w::Integer, stage::Integer = 2)
    add_scenarios!(scenariogenerator, structure(stochasticprogram), stage, n, w)
    invalidate_cache!(stochasticprogram)
    return stochasticprogram
end
"""
    sample!(stochasticprogram::StochasticProgram, sampler::AbstractSampler, n::Integer, stage::Integer = 2)

Sample `n` scenarios using `sampler` and add to the `stochasticprogram` at `stage`. Defaults to the second stage. If the `stochasticprogram` is distributed, scenarios will be distributed evenly across workers.
"""
function sample!(stochasticprogram::StochasticProgram, sampler::AbstractSampler, n::Integer, stage::Integer = 2)
    sample!(structure(stochasticprogram), stage, sampler, n)
    return stochasticprogram
end
# ========================== #

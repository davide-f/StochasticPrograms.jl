abstract type AbstractScenarioProblems{T <: AbstractFloat, S <: AbstractScenario} end

abstract type AbstractBlockStructure{N, T} <: AbstractStochasticStructure{N,T} end

# Getters #
# ========================== #
function scenarioproblems(structure::AbstractBlockStructure{N}, s::Integer = 2) where N
    s == 1 && error("Stage 1 does not have scenario problems.")
    N == 2 && (s == 2 || error("Stage $s not available in two-stage model."))
    1 < s <= N || error("Stage $s not in range 2 to $N.")
    return structure.scenarioproblems[s-1]
end
function scenario(structure::AbstractBlockStructure, i::Integer, s::Integer = 2)
    scenario(scenarioproblems(structure, s), i)
end
function scenarios(structure::AbstractBlockStructure, s::Integer = 2)
    scenarios(scenarioproblems(structure, s))
end
function expected(structure::AbstractBlockStructure, s::Integer = 2)
    return expected(scenarioproblems(structure, s)).scenario
end
function scenariotype(structure::AbstractBlockStructure, s::Integer = 2)
    return scenariotype(scenarioproblems(structure, s))
end
function probability(structure::AbstractBlockStructure, i::Integer, s::Integer = 2)
    return probability(scenarioproblems(structure, s), i)
end
function stage_probability(structure::AbstractBlockStructure, s::Integer = 2)
    return probability(scenarioproblems(structure, s))
end
function subproblem(structure::AbstractBlockStructure, i::Integer, s::Integer = 2)
    return subproblem(scenarioproblems(structure, s), i)
end
function subproblems(structure::AbstractBlockStructure, s::Integer = 2)
    return subproblems(scenarioproblems(structure, s))
end
function nsubproblems(structure::AbstractBlockStructure, s::Integer = 2)
    return nsubproblems(scenarioproblems(structure, s))
end
function nscenarios(structure::AbstractBlockStructure, s::Integer = 2)
    return nscenarios(scenarioproblems(structure, s))
end
deferred(structure::AbstractBlockStructure{N}) where N = deferred(structure, Val(N))
deferred(structure::AbstractBlockStructure, ::Val{1}) = deferred_first_stage(structure)
function deferred(structure::AbstractBlockStructure, ::Val{N}) where N
    return deferred_stage(structure, N) || deferred(structure, Val(N-1))
end
deferred_first_stage(structure::AbstractBlockStructure) = num_variables(first_stage(structure)) == 0
function deferred_stage(structure::AbstractBlockStructure{N}, s::Integer) where N
    1 <= s <= N || error("Stage $s not in range 1 to $N.")
    s == 1 && return deferred_first_stage(structure)
    nsubproblems(structure, s) < nscenarios(structure, s)
end
# ========================== #

# Setters
# ========================== #
function add_scenario!(structure::AbstractBlockStructure, scenario::AbstractScenario, stage::Integer = 2)
    add_scenario!(scenarioproblems(structure, stage), scenario)
    return nothing
end
function add_worker_scenario!(structure::AbstractBlockStructure, scenario::AbstractScenario, w::Integer, stage::Integer = 2)
    add_scenario!(scenario(structure, stage), scenario, w)
    return nothing
end
function add_scenario!(scenariogenerator::Function, structure::AbstractBlockStructure, stage::Integer = 2)
    add_scenario!(scenariogenerator, scenarioproblems(structure, stage))
    return nothing
end
function add_worker_scenario!(scenariogenerator::Function, structure::AbstractBlockStructure, w::Integer, stage::Integer = 2)
    add_scenario!(scenariogenerator, scenarioproblems(structure, stage), w)
    return nothing
end
function add_scenarios!(structure::AbstractBlockStructure, scenarios::Vector{<:AbstractScenario}, stage::Integer = 2)
    add_scenarios!(scenarioproblems(structure, stage), scenarios)
    return nothing
end
function add_worker_scenarios!(structure::AbstractBlockStructure, scenarios::Vector{<:AbstractScenario}, w::Integer, stage::Integer = 2)
    add_scenarios!(scenarioproblems(structure, stage), scenarios, w)
    return nothing
end
function add_scenarios!(scenariogenerator::Function, structure::AbstractBlockStructure, n::Integer, stage::Integer = 2)
    add_scenarios!(scenariogenerator, scenarioproblems(structure, stage), n)
    return nothing
end
function add_worker_scenarios!(scenariogenerator::Function, structure::AbstractBlockStructure, n::Integer, w::Integer, stage::Integer = 2)
    add_scenarios!(scenariogenerator, scenarioproblems(structure, stage), n, w)
    return nothing
end
function sample!(structure::AbstractBlockStructure, sampler::AbstractSampler, n::Integer, stage::Integer = 2)
    sample!(scenarioproblems(structure, stage), sampler, n)
    return nothing
end
# ========================== #

# Includes
# ========================== #
include("scenarioproblems.jl")
include("vertical.jl")
include("horizontal.jl")

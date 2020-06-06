@enum Active Initial Final

mutable struct ActiveAggregation
    active::Active

    function ActiveAggregation()
        return new(Initial)
    end
end

function shift(gap::AbstractFloat, τ::AbstractFloat)
    return gap <= τ
end

"""
    HybridAggregation

Functor object for using hybrid aggregation in an L-shaped algorithm. Create by supplying a [`HybridAggregate`](@ref) object through `aggregate ` in the `LShapedSolver` factory function and then pass to a `StochasticPrograms.jl` model.

...
# Parameters
- `initial::AbstractAggregator`: Initial aggregation scheme
- `final::AbstractAggregator`: Final aggregation scheme
- `τ::T`: The active aggregation scheme is switched from `initial` to `final` when the optimality gap decreases below `τ`
...
"""
struct HybridAggregation{T <: AbstractFloat, Agg1 <: AbstractAggregation, Agg2 <: AbstractAggregation} <: AbstractAggregation
    initial::Agg1
    final::Agg2
    τ::T
    active::ActiveAggregation

    function HybridAggregation(initial::AbstractAggregation, final::AbstractAggregation, τ::AbstractFloat)
        Agg1 = typeof(initial)
        Agg2 = typeof(final)
        T = typeof(τ)
        return new{T,Agg1,Agg2}(initial, final, τ, ActiveAggregation())
    end
end

function active(aggregation::HybridAggregation)
    if aggregation.active.active == Initial
        return aggregation.initial
    end
    return aggregation.final
end

function activate_final!(aggregation::HybridAggregation)
    aggregation.active.active = Final
    return nothing
end

function aggregate_cut!(lshaped::AbstractLShaped, aggregation::HybridAggregation, cut::HyperPlane)
    return aggregate_cut!(lshaped, active(aggregation), cut)
end

function aggregate_cut!(cutqueue::CutQueue, aggregation::HybridAggregation, metadata::MetaData, t::Integer, cut::HyperPlane, x::AbstractArray)
    return aggregate_cut!(cutqueue, active(aggregation), metadata, t, cut, x)
end

function num_thetas(num_subproblems::Integer, aggregation::HybridAggregation)
    return num_thetas(num_subproblems, active(aggregation))
end

function num_thetas(num_subproblems::Integer, aggregation::HybridAggregation, sp::DistributedScenarioProblems)
    return num_thetas(num_subproblems, active(aggregation), sp)
end

function flush!(lshaped::AbstractLShaped, aggregation::HybridAggregation)
    added = flush!(lshaped, active(aggregation))
    if shift(gap(lshaped), aggregation.τ)
        activate_final!(aggregation)
    end
    return added
end

function flush!(cutqueue::CutQueue, aggregation::HybridAggregation, metadata::MetaData, t::Integer, x::AbstractArray) where T <: AbstractFloat
    flush!(cutqueue, active(aggregation), metadata, t, x)
    if shift(fetch(metadata, t, :gap), aggregation.τ)
        activate_final!(aggregation)
    end
    return nothing
end

# API
# ------------------------------------------------------------
"""
    HybridAggregate(initial::AbstractAggregator, final::AbstractAggregator, τ::AbstractFloat)

Factory object for [`HybridAggregation`](@ref). Pass to `aggregate ` in the `LShapedSolver` factory function. See ?HybridAggregation for parameter descriptions.

"""
mutable struct HybridAggregate <: AbstractAggregator
    initial::AbstractAggregator
    final::AbstractAggregator
    τ::Float64

    function HybridAggregate(initial::AbstractAggregator, final::AbstractAggregator, τ::AbstractFloat)
        return new(initial, final, τ)
    end
end

struct InitialAggregator <: AggregationParameter end

function MOI.get(aggregator::HybridAggregate, ::InitialAggregator)
    return aggregator.initial
end

function MOI.set(aggregator::HybridAggregate, ::InitialAggregator, initial::AbstractAggregator)
    return aggregator.initial = initial
end

struct FinalAggregator <: AggregationParameter end

function MOI.get(aggregator::HybridAggregate, ::FinalAggregator)
    return aggregator.final
end

function MOI.set(aggregator::HybridAggregate, ::FinalAggregator, final::AbstractAggregator)
    return aggregator.final = final
end

function (aggregator::HybridAggregate)(num_subproblems::Integer, T::Type{<:AbstractFloat})
    initial = aggregator.initial(num_subproblems, T)
    final = aggregator.final(num_subproblems, T)
    n₁ = num_thetas(num_subproblems, initial)
    n₂ = num_thetas(num_subproblems, final)
    n₁ == n₂|| error("Inconsistent number of theta variables in hybrid aggregation: $n₁ ≠ $n₂")
    return HybridAggregation(initial, final, convert(T, aggregator.τ))
end

function remote_aggregator(aggregation::HybridAggregation, sp::AbstractScenarioProblems, w::Integer)
    return HybridAggregate(remote_aggregator(aggregation.initial, sp, w),
                           remote_aggregator(aggregation.final, sp, w),
                           aggregation.τ)
end

function str(aggregator::HybridAggregate)
    return "hybrid aggregation consisting of $(str(aggregator.initial)) and $(str(aggregator.final))"
end

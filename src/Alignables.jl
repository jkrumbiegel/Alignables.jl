module Alignables

using Rhea
using Printf
using DataStructures

export Alignable, Rect, VarRect, FloatRect, Span, SpannedAlignable, Grid, height, width, sides, Axis, constraints

abstract type Alignable end

struct Rect{T}
    left::T
    right::T
    top::T
    bottom::T
end

sides(r::Rect) = (r.left, r.right, r.top, r.bottom)

const VarRect = Rect{FVariable}
VarRect() = Rect((Variable(0.0) for i in 1:4)...)

const FloatRect = Rect{Float64}
Base.convert(::Type{FloatRect}, r::VarRect) = begin
    FloatRect(value(r.left), value(r.right), value(r.top), value(r.bottom))
end

width(r::Rect) = r.right - r.left
height(r::Rect) = r.top - r.bottom

struct Span
    rows::UnitRange{Int64}
    cols::UnitRange{Int64}
end

struct SpannedAlignable
    al::Alignable
    sp::Span
end

struct Grid <: Alignable
    content::Vector{SpannedAlignable}
    edges::VarRect
    aligns::VarRect
    nrows::Int64
    ncols::Int64
    relwidths::Vector{Float64} # n rows
    relheights::Vector{Float64} # n cols
    rowtops::Vector{FVariable}
    rowbottoms::Vector{FVariable}
    rowgapseps::Vector{FVariable} # the division lines inside row gaps
    collefts::Vector{FVariable}
    colrights::Vector{FVariable}
    colgapseps::Vector{FVariable} # the division lines inside column gaps
    unitwidth::FVariable # what is 1 relative width
    unitheight::FVariable # what is 1 relative height
    colgap::FVariable
    rowgap::FVariable
    colspacing::FVariable
    rowspacing::FVariable
    c_colspacing::Constraint
    c_rowspacing::Constraint
    margins::VarRect
    c_margins::Rect{Constraint}
end

function Grid(
        nrows, ncols;
        relwidths = nothing,
        relheights = nothing,
        colspacing = 0.0,
        rowspacing = 0.0,
        margins = FloatRect(0, 0, 0, 0)
    )
    var_colspacing = FVariable(0.0)
    var_rowspacing = FVariable(0.0)
    marginvars = VarRect()
    Grid(
        SpannedAlignable[], # content
        VarRect(), # edges
        VarRect(), # aligns
        nrows, # nrows
        ncols, # ncols
        isnothing(relwidths) ? ones(ncols) : convert(Vector{Float64}, relwidths), # relwidths
        isnothing(relheights) ? ones(nrows) : convert(Vector{Float64}, relheights), # relheights
        [FVariable(0) for i in 1:nrows], # rowtops
        [FVariable(0) for i in 1:nrows], # rowbottoms
        [FVariable(0) for i in 1:nrows-1], # rowgapseps
        [FVariable(0) for i in 1:ncols], # collefts
        [FVariable(0) for i in 1:ncols], # colrights
        [FVariable(0) for i in 1:ncols-1], # colgapseps
        FVariable(0), # unitwidth
        FVariable(0), # unitheight
        FVariable(0), # colgap
        FVariable(0), # rowgap
        var_colspacing, # colspacing
        var_rowspacing, # rowspacing
        var_colspacing == colspacing, # c_colspacing
        var_rowspacing == rowspacing, # c_rowspacing
        marginvars, # margins
        Rect( # c_margins
            marginvars.left == margins.left,
            marginvars.right == margins.right,
            marginvars.top == margins.top,
            marginvars.bottom == margins.bottom
        )
    )
end

"""
Calculates the constraints for one SpannedAlignable that is placed within
    a Grid
"""
function constraints_in(g::Grid, spanned::SpannedAlignable)
    al = spanned.al
    sp = spanned.sp

    c = OrderedDict{Symbol, Constraint}()

        # snap aligns to the correct row and column boundaries
    c[:snaptop] = al.aligns.top == g.rowtops[sp.rows.start]
    c[:snapbottom] = al.aligns.bottom == g.rowbottoms[sp.rows.stop]
    c[:snapleft] = al.aligns.left == g.collefts[sp.cols.start]
    c[:snapright] = al.aligns.right == g.colrights[sp.cols.stop]

        # ensure that grid edges always include the alignable's edges
    c[:incright] = g.edges.right >= al.edges.right + g.margins.right
    c[:incleft] = g.edges.left + g.margins.left <= al.edges.left
    c[:inctop] = g.edges.top >= al.edges.top + g.margins.top
    c[:incbottom] = g.edges.bottom + g.margins.bottom <= al.edges.bottom

    # make alignable edges push against the separators inside rows and columns
    # that allow them to grow
    # here the column and row spacing is applied as well
    if sp.cols.start > 1 # only when there's a gap left of the alignable
        c[:colgapsepleft] = g.colgapseps[sp.cols.start - 1] <= al.edges.left - 0.5 * g.colspacing
    end
    if sp.cols.stop < g.ncols  # only when there's a gap right of the alignable
        c[:colgapsepright] = g.colgapseps[sp.cols.stop] >= al.edges.right + 0.5 * g.colspacing
    end
    if sp.rows.start > 1 # only when there's a gap above the alignable
        c[:rowgapseptop] = g.rowgapseps[sp.rows.start - 1] >= al.edges.top + 0.5 * g.rowspacing
    end
    if sp.rows.stop < g.nrows # only when there's a gap below the alignable
        c[:rowgapsepbottom] = g.rowgapseps[sp.rows.stop] <= al.edges.bottom - 0.5 * g.rowspacing
    end

    c
end

function rows(g::Grid)
    [VarRect(g.aligns.left, g.aligns.right, g.rowtops[i], g.rowbottoms[i]) for i in 1:g.nrows]
end

function cols(g::Grid)
    [VarRect(g.collefts[i], g.colrights[i], g.aligns.top, g.aligns.bottom) for i in 1:g.ncols]
end

function constraints(g::Grid)

    rs = rows(g)
    cs = cols(g)

    relheights = [height(r) == g.relheights[i] * g.unitheight for (i, r) in enumerate(rs)]
    relwidths = [width(c) == g.relwidths[i] * g.unitwidth for (i, c) in enumerate(cs)]

    # these take care of the column and row order because they have to be ordered
    # correctly to have a positive width
    positive_unitheight = g.unitheight >= 0
    positive_unitwidth = g.unitwidth >= 0

    # align first and last row / column with grid aligns
    boundsalign = [
        g.rowtops[1] == g.aligns.top,
        g.rowbottoms[end] == g.aligns.bottom,
        g.collefts[1] == g.aligns.left,
        g.colrights[end] == g.aligns.right
    ]

    aligns_to_edges = [
        # edges have to be outside of or coincide with the aligns
        g.edges.top >= g.aligns.top + g.margins.top,
        g.edges.bottom + g.margins.bottom <= g.aligns.bottom,
        g.edges.left + g.margins.left <= g.aligns.left,
        g.edges.right >= g.aligns.right + g.margins.right,
        # make the aligns go as far to the edges as possible / span out the grid cells
        (g.edges.top == g.aligns.top + g.margins.top) | strong(),
        (g.edges.bottom + g.margins.bottom == g.aligns.bottom) | strong(),
        (g.edges.left + g.margins.left == g.aligns.left) | strong(),
        (g.edges.right == g.aligns.right + g.margins.right) | strong(),
    ]

    equalcolgaps = g.ncols <= 1 ? [] : [g.collefts[i+1] - g.colrights[i] == g.colgap for i in 1:g.ncols-1]
    equalrowgaps = g.nrows <= 1 ? [] : [g.rowbottoms[i] - g.rowtops[i+1] == g.rowgap for i in 1:g.nrows-1]

    positive_colgap = g.colgap >= 0
    positive_rowgap = g.rowgap >= 0

    small_colgap = (g.colgap == 0) | strong()
    small_rowgap = (g.rowgap == 0) | strong()

    # the separators have to be between their associated rows / columns
    # but only if there are more than 1 row / column respectively
    # colleftseporder = g.ncols <= 1 ? [] : [g.collefts[i+1] >= g.colgapseps[i] for i in 1:g.ncols-1]
    # colrightseporder = g.ncols <= 1 ? [] : [g.colrights[i] <= g.colgapseps[i] for i in 1:g.ncols-1]
    # rowtopseporder = g.nrows <= 1 ? [] : [g.rowtops[i+1] <= g.rowgapseps[i] for i in 1:g.nrows-1]
    # rowbottomseporder = g.nrows <= 1 ? [] : [g.rowbottoms[i] >= g.rowgapseps[i] for i in 1:g.nrows-1]


    contentconstraints = OrderedDict{Symbol, Union{Constraint, Vector{Constraint}, OrderedDict}}()
    # all the constraints of alignables the grid contains
    for (i, spanned) in enumerate(g.content)
        # constraints of the alignable itself
        contentconstraints[Symbol("$i-al")] = constraints(spanned.al)
        # append!(contentconstraints, constraints(spanned.al))
        # constraints of alignable in the grid
        contentconstraints[Symbol("$i-ingr")] = constraints_in(g, spanned)
        # append!(contentconstraints, constraints_in(g, spanned))
    end

    c = OrderedDict{Symbol, Union{Constraint, Vector{Constraint}, OrderedDict}}()

    c[:positive_unitheight] = positive_unitheight
    c[:positive_unitwidth] = positive_unitwidth
    c[:positive_colgap] = positive_colgap
    c[:positive_rowgap] = positive_rowgap
    c[:small_colgap] = small_colgap
    c[:small_rowgap] = small_rowgap
    c[:boundsalign] = boundsalign
    c[:relwidths] = relwidths
    c[:relheights] = relheights
    c[:c_colspacing] = g.c_colspacing
    c[:c_rowspacing] = g.c_rowspacing
    c[:c_margins_left] = g.c_margins.left
    c[:c_margins_right] = g.c_margins.right
    c[:c_margins_top] = g.c_margins.top
    c[:c_margins_bottom] = g.c_margins.bottom
    c[:aligns_to_edges] = aligns_to_edges
    c[:equalcolgaps] = equalcolgaps
    c[:equalrowgaps] = equalrowgaps
    c[:contentconstraints] = contentconstraints

    # #TODO put constraints in ordered dict to know which fail
    # vcat(
    #     positive_unitheight,
    #     positive_unitwidth,
    #     positive_colgap,
    #     positive_rowgap,
    #     small_colgap,
    #     small_rowgap,
    #     boundsalign,
    #     relwidths,
    #     relheights,
    #     g.c_colspacing,
    #     g.c_rowspacing,
    #     g.c_margins.left,
    #     g.c_margins.right,
    #     g.c_margins.top,
    #     g.c_margins.bottom,
    #     aligns_to_edges,
    #     equalcolgaps,
    #     equalrowgaps,
    #
    #     contentconstraints
    # )
    c
end

width(a::Alignable) = width(a.edges)
height(a::Alignable) = height(a.edges)

struct Axis <: Alignable
    edges::VarRect
    aligns::VarRect
    constraints::OrderedDict{Symbol, Constraint}
end

function Axis(left::Real, right::Real, top::Real, bottom::Real)
    edges = VarRect()
    aligns = VarRect()

    left_var = FVariable()
    right_var = FVariable()
    top_var = FVariable()
    bottom_var = FVariable()

    constraints = OrderedDict{Symbol, Constraint}()

    # make constraints from the variables with which their values can be set later
    constraints[:left] = left_var == left
    constraints[:right] = right_var == right
    constraints[:top] = top_var == top
    constraints[:bottom] = bottom_var == bottom

    constraints[:top_align] = (edges.top == aligns.top + top_var)# | strong()
    constraints[:left_align] = (edges.left == aligns.left - left_var)# | strong()
    constraints[:right_align] = (edges.right == aligns.right + right_var)# | strong()
    constraints[:bottom_align] = (edges.bottom == aligns.bottom - bottom_var)# | strong()

    constraints[:width_positive] = width(aligns) >= 0
    constraints[:height_positive] = height(aligns) >= 0

    Axis(edges, aligns, constraints)
end

constraints(a::Axis) = begin
    [c for c in values(a.constraints)]
end
# constraints(a::Axis) = begin
#     edgesaligns = [
#         (a.edges.top == a.aligns.top + a.labelsizes.top) | strong(),
#         (a.edges.bottom == a.aligns.bottom - a.labelsizes.bottom) | strong(),
#         (a.edges.left == a.aligns.left - a.labelsizes.left) | strong(),
#         (a.edges.right == a.aligns.right + a.labelsizes.right) | strong(),
#
#         width(a) >= 0,
#         height(a) >= 0
#     ]
# end

# Axis() = Axis(VarRect(), VarRect(), Rect((20 .+ rand(4) * 20)...))

Rhea.add_constraints(s::SimplexSolver, a::Alignable) = add_constraints(s, constraints(a))

Base.setindex!(g::Grid, a::Alignable, rows::S, cols::T) where {T<:Union{UnitRange,Int,Colon}, S<:Union{UnitRange,Int,Colon}} = begin

    if typeof(rows) <: Int
        rows = rows:rows
    elseif typeof(rows) <: Colon
        rows = 1:g.nrows
    end
    if typeof(cols) <: Int
        cols = cols:cols
    elseif typeof(cols) <: Colon
        cols = 1:g.ncols
    end

    if !((1 <= rows.start <= g.nrows) || (1 <= rows.stop <= g.nrows))
        error("invalid row span $rows for grid with $(g.nrows) rows")
    end
    if !((1 <= cols.start <= g.ncols) || (1 <= cols.stop <= g.ncols))
        error("invalid col span $cols for grid with $(g.ncols) columns")
    end
    push!(g.content, SpannedAlignable(a, Span(rows, cols)))
end

function Base.setindex!(g::Grid, a::Alignable, index::Int, direction::Symbol=:down)
    if index < 1 || index > g.ncols * g.nrows
        error("Invalid index $index for $(g.nrows) × $(g.ncols) grid")
    end

    if direction == :down
        (j, i) = divrem(index, g.nrows)
        j += 1
        if i == 0
            j -= 1
            i = g.nrows
        end
        g[i, j] = a
    elseif direction == :right
        (i, j) = divrem(index, g.ncols)
        i += 1
        if j == 0
            i -= 1
            j = g.ncols
        end
        g[i, j] = a
    else
        error("Invalid direction symbol $direction. Only :down or :right")
    end
end

# function Base.setindex!(g::Grid, as::Alignables)

function Base.show(io::IO, r::VarRect)
    print(io,
        "l: ", @sprintf("%.2f", value(r.left)),
        " r: ", @sprintf("%.2f", value(r.right)),
        " t: ", @sprintf("%.2f", value(r.top)),
        " b: ", @sprintf("%.2f", value(r.bottom)))
end
function Base.show(io::IO, r::FloatRect)
    print(io,
        "l: ", @sprintf("%.2f", r.left),
        " r: ", @sprintf("%.2f", r.right),
        " t: ", @sprintf("%.2f", r.top),
        " b: ", @sprintf("%.2f", r.bottom))
end
function Base.show(io::IO, g::Grid)
    println("Grid $(g.nrows)×$(g.ncols)")
    print(io, "Edges: ")
    println(io, g.edges)
    print(io, "Aligns: ")
    println(io, g.aligns)
    println("Rows:")
    for i in 1:g.nrows
        if i > 1
            @printf("  gap height %.2f with separator at %.2f\n", value(g.rowbottoms[i-1]) - value(g.rowtops[i]), value(g.rowgapseps[i-1]))
        end
        @printf("%d from %.2f to %.2f with height %.2f\n", i, value(g.rowtops[i]), value(g.rowbottoms[i]), value(g.rowtops[i]) - value(g.rowbottoms[i]))
    end
    println("Columns:")
    for i in 1:g.ncols
        if i > 1
            @printf("  gap width %.2f with separator at %.2f\n", value(g.collefts[i]) - value(g.colrights[i-1]),  value(g.colgapseps[i-1]))
        end
        @printf("%d from %.2f to %.2f with width %.2f\n", i, value(g.collefts[i]), value(g.colrights[i]), value(g.colrights[i]) - value(g.collefts[i]))
    end
end

function Base.show(io::IO, a::Axis)
    println("Axis")
    print(io, "Edges: ")
    println(io, a.edges)
    print(io, "Aligns: ")
    println(io, a.aligns)
end

function rectlines(l, r, t, b)
    x = [l, l, r, r, l]
    y = [b, t, t, b, b]
    hcat(x, y)
end

function observables(r::VarRect)
    (r.left.obs, r.right.obs, r.top.obs, r.bottom.obs)
end

include("plot.jl")

end # module

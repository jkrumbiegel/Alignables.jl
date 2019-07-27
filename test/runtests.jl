using Rhea
using Alignables
using Test
using ProgressMeter
using DataStructures

@testset "rects" begin
    r = Rect(1, 3, 2, 0)
    @test r.left == 1
    @test r.right == 3
    @test r.top == 2
    @test r.bottom == 0
    @test height(r) == 2
    @test width(r) == 2
    @test sides(r) == (1, 3, 2, 0)
end

@testset "varrects" begin
    vr = VarRect(FVariable(1), FVariable(2), FVariable(3), FVariable(4))
    @test value(vr.left) == 1
    @test value(vr.right) == 2
    @test value(vr.top) == 3
    @test value(vr.bottom) == 4

    fr = convert(FloatRect, vr)
    @test fr.left == 1
    @test fr.right == 2
    @test fr.top == 3
    @test fr.bottom == 4
end

@testset "grid solve" begin
    failures = []
    i_failure = Set()

    @showprogress 1 "Solving 1000 3x3 grid layouts..." for n = 1:1000

        nrows = 3
        ncols = 3
        g = Grid(nrows, ncols)

        for i = 1:nrows, j=1:ncols
            # g[i, j] = Axis(VarRect(), VarRect(), FloatRect(10, 10, 10, 10))
            g[i, j] = Alignables.Axis((10 .+ 20 .* rand(4))...)
        end

        s = SimplexSolver()

        widthc = width(g) == 1000
        heightc = height(g) == 1000
        leftc = g.edges.left == 0
        bottomc = g.edges.bottom == 0

        gridconstraints = constraints(g)

        add_constraints(s, [
            widthc,
            heightc,
            leftc,
            bottomc
        ])

        function add_const(c::Constraint, id::String)
            try
                add_constraint(s, c)
            catch
                push!(failures, id)
                push!(i_failure, n)
            end
        end

        function add_const(cs::Vector{Constraint}, id::String)
            for (i, c) in enumerate(cs)
                add_const(c, "$id i$i")
            end
        end

        function add_const(cd::OrderedDict, id::String)
            for (key, val) in cd
                add_const(val, "$id $key")
            end
        end

        add_const(gridconstraints, "")

    end
    println("$(length(i_failure)) failures")
    println.(sort!(unique(failures)))
    @test isempty(failures)
end

# @testset "grid observable change" begin
#     n_failures = 0
#
#     g = Grid(3, 3)
#
#     for i = 1:3, j=1:3
#         g[i, j] = Axis(VarRect(), VarRect(), FloatRect(10, 10, 10, 10))
#     end
#
#     s = SimplexSolver()
#
#     widthc = width(g) == 100
#     heightc = height(g) == 100
#     leftc = g.edges.left == 0
#     bottomc = g.edges.bottom == 0
#
#     gridconstraints = constraints(g)
#
#     add_constraints(s, [
#         widthc,
#         heightc,
#         leftc,
#         bottomc
#     ])
#     for c in gridconstraints
#         add_constraint(s, c)
#     end
#
#     for w in 101:200
#         set_constant(s, widthc, w)
#         # println(g.unitwidth)
#     end
#
# end

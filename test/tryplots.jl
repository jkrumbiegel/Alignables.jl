using Revise
using Rhea
using Makie
using Alignables

function test()
    g = Grid(4, 4, relwidths=[1, 1, 1, 2], colspacing=10, rowspacing=10, margins=FloatRect(10, 10, 10, 10))

    for i = 1:3, j=1:3
        # g[i, j] = Axis(VarRect(), VarRect(), FloatRect(10, 10, 10, 10))
        g[i, j] = Alignables.Axis((10 .+ 20 .* rand(4))...)
    end

    g[:, 4] = Alignables.Axis((10 .+ 20 .* rand(4))...)
    g[4, 1:3] = Alignables.Axis((10 .+ 20 .* rand(4))...)

    s = SimplexSolver()

    widthc = (width(g) == 600) | medium()
    heightc = (height(g) == 400) | medium()
    leftc = g.edges.left == 0
    bottomc = g.edges.bottom == 0

    gridconstraints = constraints(g)

    add_constraints(s, [
        widthc,
        heightc,
        leftc,
        bottomc
    ])
    for (i, c) in enumerate(gridconstraints)
        try
            add_constraint(s, c)
        catch
            push!(failures, i)
        end
    end

    sc = Scene()
    sc = plot!(sc, g, withcontent=true)

    g, sc, s
end

grid, s, solver = test();

function animate(solver, grid)
    frameduration = 1//30
    duration = 2
    for t in 0:frameduration:duration
        set_constant(solver, grid.content[end].al.constraints[:bottom], sin(t * pi / duration) * 50 + 20)
        sleep(frameduration)
    end
    for t in 0:frameduration:duration
        set_constant(solver, grid.content[end-1].al.constraints[:left], sin(t * pi / duration) * 50 + 20)
        sleep(frameduration)
    end
    for t in 0:frameduration:duration
        set_constant(solver, grid.content[2].al.constraints[:right], sin(t * pi / duration) * 50 + 20)
        sleep(frameduration)
    end
end
animate(solver, grid)

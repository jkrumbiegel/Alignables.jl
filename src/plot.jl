import Makie: convert_arguments, plot!, Scene, lines!, poly!, RGBAf0, Node, lift


function convert_arguments(r::Rect)

    fr = Base.convert(FloatRect, r)
    points = [
        fr.left fr.top
        fr.right fr.top
        fr.right fr.bottom
        fr.left fr.bottom
        fr.left fr.top
    ]
end

function points(r::Rect)
    fr = Base.convert(FloatRect, r)
    points = [
        fr.left fr.top
        fr.right fr.top
        fr.right fr.bottom
        fr.left fr.bottom
    ]
end

function liftpolypoints(r::VarRect)

    function rectcoords(l, r, t, b)
        [
            l t
            r t
            r b
            l b
        ]
    end

    lift(rectcoords, observables(r)...)
end

function liftrectpoints(r::VarRect)

    function rectcoords(l, r, t, b)
        [
            l t
            r t
            r b
            l b
            l t
        ]
    end

    lift(rectcoords, observables(r)...)
end

function plot!(s::Scene, g::Grid; withcontent=false)
    s = lines!(s, liftrectpoints(g.edges))
    s = lines!(s, liftrectpoints(g.aligns))
    for r in rows(g)
        s = lines!(s, liftrectpoints(r))
    end
    for c in cols(g)
        s = lines!(s, liftrectpoints(c))
    end

    if withcontent
        for c in g.content
            s = plot!(s, c)
        end
    end

    s
end

plot!(s::Scene, sp::SpannedAlignable) = plot!(s, sp.al)

function plot!(s::Scene, a::Alignables.Axis)
    s = poly!(s, liftpolypoints(a.edges), color=RGBAf0(0, 0, 0, 0.2), strokewidth = 2, strokecolor = :black)
    s = poly!(s, liftpolypoints(a.aligns), color=RGBAf0(0, 0.3, 0.5, 0.2))
end

@{
    # The MIDDLE level of the three. A producer repository drops this file at
    # its root so every render of its graphs starts from the same place,
    # without every caller having to pass the same parameters.
    #
    # Precedence, highest first:
    #   1. an explicit -Options object
    #   2. this file
    #   3. New-GraphRenderOptions' built-in defaults
    #
    # Each level is a whole-KEY merge, not a whole-object replacement: the keys
    # named here move, and every key absent from this file keeps its built-in
    # value. That is why this file can be three lines long and still be
    # meaningful.
    #
    # A key New-GraphRenderOptions has no parameter for is a hard error rather
    # than a line nobody reads.

    Layout    = 'testorder'
    ColorBy   = 'blastRadius'
    ZoomSpeed = 2.5

    # ColorBy names a metric here, so node fill is a heat ramp over that
    # measure and KindColor is not consulted at all. Setting the ramp rather
    # than the kind map is the point: which key matters depends on ColorBy.
    Theme     = @{
        HeatRamp = @('#2c3e50', '#4a6fa5', '#c9a227', '#e07a3f', '#d94f3d')
    }
}

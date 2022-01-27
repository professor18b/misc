def process_range(rangelist, current):
    if current < rangelist[0]:
        rangelist[0] = current
        if rangelist[1] == 0:
            rangelist[1] = current
    elif current > rangelist[1]:
        rangelist[1] = current
        if rangelist[0] == 0:
            rangelist[0] = current
    return


def add_plot(fig, files, index):
    file = files[index]
    sample_file = open(file, "r")
    sample_lines = sample_file.readlines()
    x = []
    y = []
    z = []
    i = 0
    x_range = [1, 0]
    y_range = [1, 0]
    z_range = [1, 0]

    for line in sample_lines:
        if line.startswith("acceleration -"):
            line = line.removeprefix("acceleration -")
            position_strings = line.split(",")
            assert len(position_strings) == 3
            value = float(position_strings[0].removeprefix(" x: "))
            process_range(x_range, value)
            x.append(value)

            value = float(position_strings[1].removeprefix(" y: "))
            process_range(y_range, value)
            y.append(value)

            value = float(position_strings[2].removeprefix(" z: "))
            process_range(z_range, value)
            z.append(value)

            # print(f"x:{x[i]} in {xRange}, y:{y[i]} in {yRange}, z:{z[i]} in {zRange}")
            i += 1

    print(f"x in {x_range}, y in {y_range}, z in {z_range}")
    ax = fig.add_subplot(1, len(files), index + 1, projection="3d")
    ax.plot3D(x, y, z, 'red')
    ax.scatter3D(x, y, z, c=x, cmap='Reds')
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_zlabel("z")
    return

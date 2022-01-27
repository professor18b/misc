import matplotlib.pyplot as plt

import plot_util

# from matplotlib import cm
# from matplotlib.ticker import LinearLocator, FormatStrFormatter
# from mpl_toolkits.mplot3d import axes3d

# fig = plt.figure()
# ax = fig.add_subplot(projection="3d")
#
# zline = np.linspace(0, 15, 1000)
# xline = np.sin(zline)
# yline = np.cos(zline)
# ax.plot3D(xline, yline, zline, 'gray')
#
# zdata = 15 * np.random.random(100)
# xdata = np.sin(zdata) + 0.1 * np.random.random(100)
# ydata = np.cos(zdata) + 0.1 * np.random.random(100)
# ax.scatter3D(xdata, ydata, zdata, c=zdata, cmap='Greens')
#
# plt.show()

# x = np.linspace(0, 15, 10)
# y = np.linspace(15, 5, 10)
# z = np.linspace(0, 20, 10)


samples = ["sample_front_back.txt", "sample_up_down.txt"]
figure = plt.figure()
plot_util.add_plot(figure, samples, 0)
plot_util.add_plot(figure, samples, 1)
plt.show()

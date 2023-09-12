import matplotlib.pyplot as plt

PATH = "logs.log"

modes = {}

with open(PATH, 'r') as fin:
    while True:
        size = fin.readline()
        if not size:
            break
        size = int(size.split()[-1])
        title = fin.readline()
        el_time = float(fin.readline())
        if title not in modes:
            modes[title] = ([], [])
        modes[title][0].append(size)
        modes[title][1].append(el_time)


fig = plt.figure(figsize=(8, 15))


plt.title("Сравнительная таблица")
for key in modes.keys():
    pair = modes[key]
    plt.plot(pair[0], pair[1], label=key)


plt.grid()
plt.xlabel("Количество потоков")
plt.ylabel("Время, мс")

plt.legend()
plt.show()

fig.savefig('temp.png', dpi=fig.dpi)


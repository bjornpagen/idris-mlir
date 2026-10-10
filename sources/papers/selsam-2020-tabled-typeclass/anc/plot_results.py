import matplotlib.pyplot as plt
import csv

def load_data(filename):
    results = {}
    first = True
    with open(filename) as csvfile:
        reader = csv.reader(csvfile, delimiter=',')
        for row in reader:
            if first:
                ns = [float(s) for s in row[1:]]
                first = False
            else:
                results[row[0]] = [float(s) for s in row[1:]]

    return ns, results

def plot_results(ns, results, title, xlabel, ylabel, grid):
    colors  = {"Coq":"red", "Lean4":"blue", "Lean4 (without shortcircuit)":"red", "Lean3":"orange",
               "GHC":"green", "Isa":"brown", "Rust":"yellow", "Scala":"purple", "Agda":"green"}
    fig, ax = plt.subplots()
    ax.axis(auto=True)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    for key in results:
        print(key, results[key])
        ax.plot(ns[:len(results[key])], results[key], label=key, color=colors[key])

    ax.legend()
    ax.grid(grid)
    plt.show()

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--experiment', action='store', dest='experiment', type=str, default=None)
    parser.add_argument('--grid', action='store', dest='grid', type=int, default=0)
    opts = parser.parse_args()

    if opts.experiment == "diamonds":
        title  = "Typeclass resolution procedures on (failing) towers of diamonds"
        xlabel = "Height of tower"
        ylabel = "Number of seconds"
    elif opts.experiment == "append":
        title  = "Typeclass resolution procedures appending two lists"
        xlabel = "Size of input lists"
        ylabel = "Number of seconds"
    else:
        raise Exception("Unexpected experiment name: %s" % opts.experiment)

    ns, results = load_data("%s.csv" % opts.experiment)
    plot_results(ns=ns, results=results, title=title, xlabel=xlabel, ylabel=ylabel, grid=opts.grid)

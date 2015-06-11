benchmark-wrapper
=================

## bench-range.pl

Produce a CSV file from a sequence of httperf or siege runs.

`bench-range.pl [options] --steps X --engine=[httperf|siege] [[--] I<engine-options>]`

See `bench-range.pl --man` for a complete documentation, including example.

## bench-graph.pl

Produce a graph, using Gnuplot, from the tab-separated data files (produced by `bench-range.pl`).

`bench-graph.pl [options] source.tsv [source2.csv ...]`

See `bench-graph.pl --man` for a complete documentation, including example.

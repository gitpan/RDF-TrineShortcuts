use Test::More tests => 2;
BEGIN { use_ok('RDF::TrineShortcuts') };

my $in    = "<http://example.com/s> <http://example.com/p> <http://example.com/o> .\r\n";
my $model = rdf_parse($in);

ok(rdf_query("ASK WHERE { $in }", $model), "rdf_query OK");

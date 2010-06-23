use Test::More tests => 4;
BEGIN { use_ok('RDF::TrineShortcuts') };

my $in    = "<http://example.com/s> <http://example.com/p> <http://example.com/o> .\r\n";
my $model = rdf_parse($in);

ok($model->count_statements == 1, "rdf_parse OK");

my $type;

ok(rdf_string($model, 'Canonical', media_type=>\$type) eq $in, "rdf_string OK");

is($type, 'text/plain', 'media type reporting OK');
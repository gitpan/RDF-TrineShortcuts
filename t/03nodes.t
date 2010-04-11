use Test::More tests => 4;
use RDF::TrineShortcuts qw(:all);

my $model = rdf_parse();

$model->add_statement(rdf_statement(
	['s', base=>'http://example.com/', type=>'uri'],
	'http://example.com/p',
	'_:o'
	));

$model->add_statement(rdf_statement(
	['http://example.com/s'],
	'http://example.com/p',
	['o', lang=>'en']
	));

$model->add_statement(rdf_statement('<http://example.com/s> <http://example.com/p> <http://example.com/o>'));

is($model->count_statements, 3);

ok(rdf_query('ASK WHERE { <http://example.com/s> <http://example.com/p> "o"@en. }', $model));

ok(rdf_query('ASK WHERE { <http://example.com/s> <http://example.com/p> ?o . FILTER(isBlank(?o)) }', $model));

ok(rdf_query('ASK WHERE { <http://example.com/s> <http://example.com/p> <http://example.com/o> . }', $model));


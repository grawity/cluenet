"noop" => {
	requires =>
	["noop"],

	command =>
	sub {
		$rpc->authenticate;
		$rpc->noop;
	},
};

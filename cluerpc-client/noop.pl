"noop" => {
	command =>
	sub {
		check $r = authenticate;
		check $r = request(cmd => "noop");
	},
};

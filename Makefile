install:
	mkdir -p ~/.local/bin
	cp timers.sh ~/.local/bin/timers
	chmod +x ~/.local/bin/timers
	echo 'export PATH=$$HOME/.local/bin:$$PATH' >> ~/.bashrc
	echo 'export PATH=$$HOME/.local/bin:$$PATH' >> ~/.zshrc
	/bin/bash -c "source ~/.bashrc || source ~/.zshrc"

uninstall:
	rm -f ~/.local/bin/timers
	sed -i '/export PATH=\$HOME\/.local\/bin:\$PATH/d' ~/.bashrc
	sed -i '/export PATH=\$HOME\/.local\/bin:\$PATH/d' ~/.zshrc

test:
	./tests/test.sh

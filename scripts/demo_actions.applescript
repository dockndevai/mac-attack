-- Drives the demo: spawn humans, fire effects, chaos mode. Clicks by button title.
tell application "System Events"
	tell process "MacAttack"
		set frontmost to true
		delay 1
		click button "Spawn Human" of window 1
		delay 4
		click button "Spawn 2 Humans" of window 1
		delay 6
		click button "Bubble Attack" of window 1
		delay 5
		click button "Duck Rain" of window 1
		delay 5
		click button "Confetti" of window 1
		delay 5
		click button "Chaos Mode" of window 1
		delay 10
		click button "Trigger Laya" of window 1
		delay 8
	end tell
end tell

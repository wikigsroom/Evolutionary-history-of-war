package main

import "testing"

func controlFixture() MatchControl {
	return MatchControl{Seats: []SeatControl{{PlayerID: "left", Connected: true, Loaded: true, NextSeq: 1, LastSeenMS: 100000}, {PlayerID: "right", Connected: true, Loaded: true, NextSeq: 1, LastSeenMS: 100000}}, LastAccountedMS: 100000}
}
func controlAdvance(c *MatchControl, duration int64) (int, string) {
	winner := -1
	reason := ""
	for elapsed := int64(100); elapsed <= duration; elapsed += 100 {
		now := c.LastAccountedMS + 100
		for i := range c.Seats {
			if c.Seats[i].Connected {
				c.Seats[i].LastSeenMS = now
			}
		}
		_, winner, reason = accountControl(c, "RUNNING", now)
		if reason != "" {
			return winner, reason
		}
	}
	return winner, reason
}
func TestDisconnectLimits(t *testing.T) {
	for iteration := 0; iteration < 1000; iteration++ {
		c := controlFixture()
		disconnectSeat(&c.Seats[0], 100000)
		if _, reason := controlAdvance(&c, 3000); reason != "" || !c.Paused {
			t.Fatal("first short absence must be paused")
		}
		if _, reason := controlAdvance(&c, 6000); reason != "" || c.Paused {
			t.Fatal("army resumes after bounded pause")
		}
		if winner, reason := controlAdvance(&c, 111000); reason != "DISCONNECT_FORFEIT" || winner != 1 {
			t.Fatal("single absence must end at 120 seconds")
		}
	}
}
func TestBothOfflineNoInventedWinner(t *testing.T) {
	for iteration := 0; iteration < 1000; iteration++ {
		c := controlFixture()
		disconnectSeat(&c.Seats[0], 100000)
		disconnectSeat(&c.Seats[1], 100000)
		_, _, _ = accountControl(&c, "RUNNING", 100000)
		winner, reason := controlAdvance(&c, 60000)
		if reason != "ABANDONED" || winner != -1 {
			t.Fatal("both offline cannot create a winner")
		}
	}
}
func TestCumulativeOfflineCannotReset(t *testing.T) {
	c := controlFixture()
	for round := 0; round < 3; round++ {
		disconnectSeat(&c.Seats[0], c.LastAccountedMS)
		winner, reason := controlAdvance(&c, 60000)
		if round == 2 {
			if reason != "DISCONNECT_FORFEIT" || winner != 1 {
				t.Fatal("cumulative 180 seconds did not forfeit")
			}
			return
		}
		if reason != "" {
			t.Fatal("early forfeit")
		}
		c.Seats[0].Connected = true
		c.Seats[0].OfflineSinceMS = 0
		controlAdvance(&c, 1000)
	}
}
func TestPlatformGapDoesNotConsumePlayerGrace(t *testing.T) {
	c := controlFixture()
	disconnectSeat(&c.Seats[0], 100000)
	controlAdvance(&c, 10000)
	before := c.Seats[0].OfflineTotalMS
	_, _, _ = accountControl(&c, "RUNNING", c.LastAccountedMS+15000)
	if c.Seats[0].OfflineTotalMS != before {
		t.Fatal("platform downtime charged to player")
	}
}
func TestLoadingTimeoutNoVictory(t *testing.T) {
	c := controlFixture()
	c.Seats[1].Loaded = false
	c.LoadingDeadlineMS = 100100
	_, winner, reason := accountControl(&c, "LOADING", 100100)
	if winner != -1 || reason != "LOADING_TIMEOUT" {
		t.Fatal("loading timeout is not a forfeit")
	}
}

func TestFailedGatewayCannotForfeitAPlayer(t *testing.T) {
	c := controlFixture()
	disconnectSeat(&c.Seats[0], 100000)
	before := c.Seats[0].OfflineTotalMS
	for i := 0; i < 300; i++ {
		_, winner, reason := platformPause(&c, "RUNNING", c.LastAccountedMS+100)
		if c.Seats[0].OfflineTotalMS != before || winner != -1 {
			t.Fatal("gateway outage charged to the player")
		}
		if i < 299 && reason != "" {
			t.Fatal("platform aborted before recovery deadline")
		}
	}
	_, winner, reason := platformPause(&c, "RUNNING", c.LastAccountedMS+100)
	if winner != -1 || reason != "SERVER_ABORTED" {
		t.Fatal("platform failure invented a winner")
	}
}
func TestMirrorActionsBothSequenceOne(t *testing.T) {
	commands := []Object{{"side": int64(0), "player_id": "a", "client_seq": int64(1), "apply_tick": int64(2)}, {"side": int64(1), "player_id": "b", "client_seq": int64(1), "apply_tick": int64(2)}}
	sortCommands(commands, 0)
	if number(commands[0]["side"]) != 0 {
		t.Fatal("first priority")
	}
	sortCommands(commands, 3)
	if number(commands[0]["side"]) != 1 {
		t.Fatal("alternating priority")
	}
}

package main

// Time comes from the gateway, never from client timestamps or frozen simulation ticks.
func accountControl(c *MatchControl, phase string, now int64) (string, int, string) {
	delta := now - c.LastAccountedMS
	if delta < 0 {
		delta = 0
	}
	if delta > 1500 {
		// The referee/gateway was unavailable: do not charge absence during platform downtime.
		for i := range c.Seats {
			seat := &c.Seats[i]
			if seat.OfflineSinceMS > 0 {
				seat.OfflineSinceMS += delta
			}
			if seat.PauseUntilMS > 0 {
				seat.PauseUntilMS += delta
			}
		}
		if c.BothOfflineSinceMS > 0 {
			c.BothOfflineSinceMS += delta
		}
		c.LoadingDeadlineMS += delta
		delta = 0
	}
	c.LastAccountedMS = now
	c.Paused = false
	c.PauseReason = ""
	if phase == "LOADING" {
		if len(c.Seats) == 2 && c.Seats[0].Loaded && c.Seats[1].Loaded && c.Seats[0].Connected && c.Seats[1].Connected {
			phase = "RUNNING"
		}
		if phase == "LOADING" {
			c.Paused = true
			c.PauseReason = "LOADING"
			if now >= c.LoadingDeadlineMS {
				return phase, -1, "LOADING_TIMEOUT"
			}
			return phase, -1, ""
		}
	}
	for i := range c.Seats {
		seat := &c.Seats[i]
		if seat.Connected && now-seat.LastSeenMS >= 8000 {
			disconnectSeat(seat, now)
		}
		if !seat.Connected && seat.Loaded {
			seat.OfflineTotalMS += delta
		}
	}
	if c.Seats[0].Surrender && c.Seats[1].Surrender {
		return phase, 2, "BOTH_SURRENDERED"
	}
	for i, seat := range c.Seats {
		if seat.Surrender {
			return phase, 1 - i, "SURRENDER"
		}
	}
	both := !c.Seats[0].Connected && !c.Seats[1].Connected
	if both {
		if c.BothOfflineSinceMS == 0 {
			c.BothOfflineSinceMS = now
		}
		c.Paused = true
		c.PauseReason = "BOTH_DISCONNECTED"
		if now-c.BothOfflineSinceMS >= 60000 {
			return phase, -1, "ABANDONED"
		}
	} else {
		c.BothOfflineSinceMS = 0
		for i := range c.Seats {
			seat := &c.Seats[i]
			if !seat.Connected && seat.Loaded {
				if now-seat.OfflineSinceMS >= 120000 || seat.OfflineTotalMS >= 180000 {
					return phase, 1 - i, "DISCONNECT_FORFEIT"
				}
				if now < seat.PauseUntilMS && seat.PauseUsedMS < 15000 {
					c.Paused = true
					c.PauseReason = "TECHNICAL_PAUSE"
					spent := delta
					if spent > 15000-seat.PauseUsedMS {
						spent = 15000 - seat.PauseUsedMS
					}
					seat.PauseUsedMS += spent
				}
			}
		}
	}
	return phase, -1, ""
}
func disconnectSeat(seat *SeatControl, now int64) {
	if !seat.Connected {
		return
	}
	seat.Connected = false
	seat.OfflineSinceMS = now
	remaining := int64(15000) - seat.PauseUsedMS
	if remaining > 8000 {
		remaining = 8000
	}
	if remaining < 0 {
		remaining = 0
	}
	seat.PauseUntilMS = now + remaining
}

func platformPause(c *MatchControl, phase string, now int64) (string, int, string) {
	delta := now - c.LastAccountedMS
	if delta < 0 {
		delta = 0
	}
	if c.PlatformSinceMS == 0 {
		c.PlatformSinceMS = now
	}
	for i := range c.Seats {
		seat := &c.Seats[i]
		if seat.OfflineSinceMS > 0 {
			seat.OfflineSinceMS += delta
		}
		if seat.PauseUntilMS > 0 {
			seat.PauseUntilMS += delta
		}
		seat.LastSeenMS += delta
	}
	if c.BothOfflineSinceMS > 0 {
		c.BothOfflineSinceMS += delta
	}
	c.LoadingDeadlineMS += delta
	c.LastAccountedMS = now
	c.Paused = true
	c.PauseReason = "SERVER_RECOVERING"
	if now-c.PlatformSinceMS >= 30000 {
		return phase, -1, "SERVER_ABORTED"
	}
	return phase, -1, ""
}

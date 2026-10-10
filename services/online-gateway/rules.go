package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Rules struct {
	Manifest Object
	Tables   map[string]map[string]Object
}

func loadRules(project string) (*Rules, error) {
	r := &Rules{Tables: map[string]map[string]Object{}}
	b, err := os.ReadFile(filepath.Join(project, "assets", "data", "online-manifest.json"))
	if err != nil {
		return nil, fmt.Errorf("generate online manifest before starting server")
	}
	if err = json.Unmarshal(b, &r.Manifest); err != nil {
		return nil, err
	}
	for name, expected := range object(r.Manifest["files"]) {
		clean := filepath.Clean(filepath.FromSlash(name))
		if filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
			return nil, fmt.Errorf("invalid manifest path")
		}
		raw, e := os.ReadFile(filepath.Join(project, clean))
		if e != nil {
			return nil, fmt.Errorf("simulation dependency is missing: %s", name)
		}
		if strings.HasSuffix(name, ".gd") {
			raw = bytes.ReplaceAll(raw, []byte("\r\n"), []byte("\n"))
		}
		hash := sha256.Sum256(raw)
		if hex.EncodeToString(hash[:]) != stringValue(expected) {
			return nil, fmt.Errorf("simulation dependency changed; regenerate manifest: %s", name)
		}
	}
	for _, name := range []string{"heroes", "skills", "specializations", "relics", "talents"} {
		b, err = os.ReadFile(filepath.Join(project, "assets", "data", name+".json"))
		if err != nil {
			return nil, err
		}
		var rows []Object
		if err = json.Unmarshal(b, &rows); err != nil {
			return nil, err
		}
		r.Tables[name] = map[string]Object{}
		for _, row := range rows {
			r.Tables[name][stringValue(row["id"])] = row
		}
	}
	return r, nil
}
func contains(v any, s string) bool {
	a, _ := v.([]any)
	for _, x := range a {
		if x == s {
			return true
		}
	}
	return false
}
func (r *Rules) compatible(body Object) error {
	if body["protocol_version"] != "1.0" || body["simulation_hash"] != r.Manifest["simulation_hash"] || body["ruleset_id"] != "pvp-classic-v1" {
		return failure("VERSION_MISMATCH", 426)
	}
	return nil
}
func (r *Rules) loadout(body Object) (Object, error) {
	l, ok := body["loadout"].(map[string]any)
	if !ok {
		return nil, failure("INVALID_LOADOUT", 400)
	}
	for key := range l {
		if key != "heroId" && key != "specializationId" && key != "commonSkillIds" && key != "relicIds" && key != "talentIds" {
			return nil, failure("INVALID_LOADOUT", 400)
		}
	}
	h := r.Tables["heroes"][stringValue(l["heroId"])]
	if h == nil || !contains(h["specializationIds"], stringValue(l["specializationId"])) {
		return nil, failure("INVALID_LOADOUT", 400)
	}
	for _, key := range []string{"commonSkillIds", "relicIds", "talentIds"} {
		a, ok := l[key].([]any)
		limit := map[string]int{"commonSkillIds": 2, "relicIds": 2, "talentIds": 6}[key]
		if !ok || len(a) > limit || (key == "commonSkillIds" && len(a) != 2) {
			return nil, failure("INVALID_LOADOUT", 400)
		}
		table := map[string]string{"commonSkillIds": "skills", "relicIds": "relics", "talentIds": "talents"}[key]
		seen := map[string]bool{}
		for _, id := range a {
			s, ok := id.(string)
			row := r.Tables[table][s]
			if !ok || row == nil || seen[s] || (table == "skills" && row["category"] != "common") {
				return nil, failure("INVALID_LOADOUT", 400)
			}
			seen[s] = true
		}
	}
	talents := append([]any{}, l["talentIds"].([]any)...)
	sort.SliceStable(talents, func(i, j int) bool {
		return number(r.Tables["talents"][stringValue(talents[i])]["tier"]) < number(r.Tables["talents"][stringValue(talents[j])]["tier"])
	})
	points := map[string]int64{}
	for _, id := range talents {
		row := r.Tables["talents"][stringValue(id)]
		branch := stringValue(row["branch"])
		if points[branch] < (number(row["tier"])-1)*2 {
			return nil, failure("INVALID_LOADOUT", 400)
		}
		points[branch]++
	}
	return l, nil
}

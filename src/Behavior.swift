import Cocoa

// Поведение кота: нужды, выбор действия (Reflex/Utility), восприятие, исполнение состояний.
extension AppDelegate {
    func enter(_ s: St) {
        st = s; stTicks = 0; hopOffset = 0
        // гасим несовместимые намерения, чтобы не возникало невозможных комбинаций
        switch s {
        case .sleep, .zoomies, .hunt, .play:         // никаких миссий
            toFood = false; toPlay = false; goingAway = false; leaving = false; eating = false; eatingRef = nil
        case .idle:                                  // idle не «уходит»; еда выставляется отдельно после прихода
            goingAway = false; leaving = false
        case .walk:                                  // на ходу не грызём (toFood/goingAway ставит вызывающий)
            eating = false; eatingRef = nil
        case .digging, .away, .falling:
            break                                    // управляются своей логикой
        }
        switch s {
        case .sleep:   stDur = Int.random(in: 600...1600)
        case .idle:    stDur = Int.random(in: 40...110)
        case .walk:    stDur = 0
        case .digging: stDur = Int.random(in: 30...50)      // ~3–5 c копает
        case .away:    stDur = Int.random(in: 1800...6000)  // 3–10 мин гуляет
        case .falling: stDur = 0
        case .hunt:    stDur = 30
        case .play:    stDur = 8
        case .zoomies: stDur = 0; zoomReps = Int.random(in: 5...10); zoomHop = 0
                       targetX = Bool.random() ? leftEdge() : rightEdge()
        }
    }

    // центр БЛИЖАЙШЕЙ кучки: внутри кучи усредняем (встаёт по центру),
    // но между раздельными кучами не садится — идёт к ближайшей
    func foodTargetX() -> CGFloat? {
        let xs = kibbles.filter { $0.landed && !$0.dragging }.map { $0.x }.sorted()
        guard !xs.isEmpty else { return nil }
        var clusters: [[CGFloat]] = [[xs[0]]]
        for v in xs.dropFirst() {
            if v - clusters[clusters.count - 1].last! <= SIZE / 2 {   // тот же кластер
                clusters[clusters.count - 1].append(v)
            } else {
                clusters.append([v])                                   // новая кучка
            }
        }
        let centers = clusters.map { $0.reduce(0, +) / CGFloat($0.count) }
        return centers.min(by: { abs($0 - x) < abs($1 - x) })
    }

    func decideNext() {
        toFood = false; toPlay = false; goingAway = false; leaving = false   // свежее решение — без залипших намерений
        if hunger > EAT_HUNGER, let c = foodTargetX() {   // идёт к корму только если голоден
            toFood = true; targetX = c; enter(.walk); return
        }

        let hN = hunger                                     // 0..1 — насколько голоден
        let hour = Calendar.current.component(.hour, from: Date())
        let bedtime = hour >= 22 || hour < 7                // вечером укладывается
        let act = dayEnergy(hour)                           // циркадная активность (утро бодр, обед вял, вечер подъём)

        // веса действий по потребностям и времени суток
        var wSleep = (1.4 - energy) + (bedtime ? 2.5 : (1.0 - act))     // устал/ночь → спать
        var wWalk = (0.5 + boredom * 0.9 + energy * 0.3) * (0.4 + act)  // скучно/бодр → бродить
        var wZoom = max(0, boredom * energy * (0.4 + hN)) * act         // → носиться
        var wIdle = 0.5                                                 // посидеть/умыться

        // настроение дня меняет акценты
        switch mood {
        case .playful: wZoom *= 2.2; wWalk *= 1.4; wSleep *= 0.7
        case .lazy:    wSleep *= 1.7; wWalk *= 0.6; wZoom *= 0.4
        case .curious: wWalk *= 1.8; wIdle *= 0.7
        case .hungry:  wZoom *= 1.5; wWalk *= 1.2
        case .normal:  break
        }

        if bedtime { wSleep += 3; wWalk *= 0.3; wZoom *= 0.05; wIdle *= 0.4 }   // вечер/ночь — в сон

        let weights: [(St, Double)] = [(.sleep, wSleep), (.walk, wWalk), (.zoomies, wZoom), (.idle, wIdle)]
        let total = weights.reduce(0) { $0 + max(0, $1.1) }
        var pick = St.idle
        if total > 0 {                                  // гард: пустой/некорректный набор весов → idle
            var r = Double.random(in: 0..<total)
            for (s, w) in weights { if r < max(0, w) { pick = s; break }; r -= max(0, w) }
        }

        let awayChance = (mood == .curious) ? 0.16 : 0.07       // любопытный чаще уходит «за стену»
        switch pick {
        case .zoomies:
            enter(.zoomies)
        case .walk:
            if Double.random(in: 0..<1) < awayChance {          // своенравно уходит за стену
                goingAway = true; awayLeft = Bool.random()
                targetX = awayLeft ? leftEdge() : rightEdge()
                enter(.walk)
            } else {
                targetX = randomX(); enter(.walk)
            }
        case .sleep:
            enter(.sleep)
        default:
            enter(.idle)
        }
    }

    // ——— Utility-мозг: нужды через response-кривые → взвешенный выбор с инерцией ———
    func ramp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {   // piecewise-linear 0..1
        if v <= lo { return 0 }; if v >= hi { return 1 }; return (v - lo) / (hi - lo)
    }

    // циркадная активность по часу: утро бодрый, обед вялый, вторая половина дня — второй подъём, ночь — сон
    func dayEnergy(_ hour: Int) -> Double {
        switch hour {
        case 7...8:   return 0.7    // только проснулся, раскачивается
        case 9...13:  return 1.3    // утро/день — самый энергичный
        case 14...16: return 0.35   // после обеда клонит в сон (сиеста)
        case 17...20: return 1.15   // вечер — второй подъём
        case 21:      return 0.5    // вечер — успокаивается
        default:      return 0.12   // ночь (22..6) — почти всегда спит
        }
    }
    // сейчас «ночь/отбой» (не игривый, спит подолгу)
    var bedtimeNow: Bool { let h = Calendar.current.component(.hour, from: Date()); return h >= 22 || h < 7 }

    func utilityDecide() {
        toFood = false; toPlay = false; goingAway = false; leaving = false
        if hunger > EAT_HUNGER, let c = foodTargetX() { toFood = true; targetX = c; enter(.walk); return }

        let hour = Calendar.current.component(.hour, from: Date())
        let bedtime = hour >= 22 || hour < 7        // вечером пора укладываться спать
        let act = dayEnergy(hour)                   // циркадная активность 0..1.3 (утро бодр, обед вял, вечер второй подъём)
        if !bedtime && energy > 0.45 && Double.random(in: 0..<1) < 0.10 * act { enter(.zoomies); return }   // днём иногда внезапно «носится»

        // полезности из нужд (response-кривые: «игнорить до порога, потом расти»), масштаб по времени суток
        var uSleep = ramp(1 - energy, 0.35, 0.95) * (bedtime ? 2.0 : (1.4 - act))  // спит, когда устал; вечером — сильно
        var uWalk  = (0.7 + ramp(boredom, 0.05, 0.7) * 1.0 + energy * 0.2) * (0.4 + act)  // спокойная прогулка
        var uZoom  = ramp(boredom, 0.6, 1.0) * energy * act               // беготня — когда бодр, скучно и день активный
        var uIdle  = 0.6                                                  // посидеть/умыться

        switch mood {
        case .playful: uZoom *= 1.8; uWalk *= 1.3; uSleep *= 0.8
        case .lazy:    uSleep *= 1.6; uWalk *= 0.7; uZoom *= 0.4
        case .curious: uWalk *= 1.6; uIdle *= 0.7
        case .hungry:  uZoom *= 1.3; uWalk *= 1.2
        case .normal:  break
        }

        // лёгкая инерция активным состояниям (но НЕ сну — иначе пересыпает)
        switch st {
        case .walk:    uWalk *= 1.15
        case .zoomies: uZoom *= 1.1
        case .idle:    uIdle *= 1.1
        default: break
        }

        if bedtime { uSleep += 2.5; uWalk *= 0.3; uZoom *= 0.05; uIdle *= 0.4 }   // вечер/ночь — сильно тянет в сон

        let weights: [(St, Double)] = [(.sleep, uSleep), (.walk, uWalk), (.zoomies, uZoom), (.idle, uIdle)]
        let total = weights.reduce(0) { $0 + max(0, $1.1) }
        var pick = St.idle
        if total > 0 {
            var r = Double.random(in: 0..<total)
            for (s, w) in weights { if r < max(0, w) { pick = s; break }; r -= max(0, w) }
        }

        let awayChance = (mood == .curious) ? 0.16 : 0.07
        switch pick {
        case .zoomies: enter(.zoomies)
        case .walk:
            if Double.random(in: 0..<1) < awayChance {
                goingAway = true; awayLeft = Bool.random()
                targetX = awayLeft ? leftEdge() : rightEdge()
                enter(.walk)
            } else { targetX = randomX(); enter(.walk) }
        case .sleep: enter(.sleep)
        default: enter(.idle)
        }
    }

    // Один тик: общая «преамбула» (нужды + привлечение корма) + исполнение состояния.
    // Решение «что дальше» инъектируется: Reflex → рандом, Utility → нужды/полезность.
    func reflexStep()  { stepPreamble(); runState(decide: { self.decideNext() }) }
    func utilityStep() {
        stepPreamble()
        if huntCool > 0 { huntCool -= 1 }
        perceive()                                   // охота на курсор (только Utility)
        playAttract()                                // гоняется за клубком (только Utility)
        runState(decide: { self.utilityDecide() })
    }

    // Восприятие окружения: мышь прямо НАД котом в зоне досягаемости → вертикальный подскок.
    func perceive() {
        guard mood == .playful, !bedtimeNow,          // охотится только в игривом настроении и не ночью
              huntCool == 0, !eating, !toFood, !goingAway, !leaving,
              st == .idle || st == .walk || st == .zoomies else { hoverTicks = 0; return }
        let m = NSEvent.mouseLocation
        let above = m.y - y                         // насколько мышь выше кота
        if abs(m.x - x) < 75 && above > SIZE * 1.5 && above < 260 {   // мышь заметно ВЫШЕ кота (≥1.5 роста) — чтоб был настоящий прыжок
            hoverTicks += 1
            if hoverTicks >= 6 {                    // мышь зависла (~0.6с), а не пролетела
                hoverTicks = 0
                huntHopH = min(above, 250) - SIZE / 2   // поднять ВЕРХНЮЮ точку кота к курсору (центр на L ниже)
                huntStartX = x
                huntAimX = min(max(m.x, leftEdge()), rightEdge())   // прыгает В СТОРОНУ мыши
                enter(.hunt)
            }
        } else {
            hoverTicks = 0
        }
    }

    // Игра с клубком: если клубок есть и кот не очень устал — всегда бежит к нему
    // (пока клубок не надоест). Еда в приоритете.
    func playAttract() {
        guard let k = preferredYarn(), !k.dragging, !eating, !toFood, !goingAway, !leaving, !bedtimeNow else {
            toPlay = false; return                       // нет мяча/занят/ночь — не делаем вид, что бежим
        }
        if toPlay { targetX = k.x; return }              // уже бежит к мячу — не передумывает на полпути
        if playCool > 0 { return }                       // только что ударил — пауза, пусть мяч отлетит (не семеним вокруг)

        // «хочу играть» = насколько не наигрался (1-playSat) × насколько есть силы (energy).
        // Выдохся (energy низкая) → НЕ играет, лежит и копит силы. Скука с одним мячом гасит интерес
        // отдельно (playSat). Бодро гоняет снова, отдохнув ИЛИ когда подкинули новый/тронули мяч (playSat=0).
        let want = (1 - playSat) * ramp(energy, 0.2, 0.6)
        guard Double.random(in: 0..<1) < want * 0.3 else { return }
        switch st {
        case .walk:            toPlay = true; targetX = k.x          // прервать обычную прогулку ради мяча
        case .idle, .zoomies:  toPlay = true; targetX = k.x; enter(.walk)   // откликается, только если бодрствует
        default: break         // спит — спящего ради мяча НЕ будим
        }
    }

    // Толчок лапой, по очереди в разные стороны, разной силой — то слабо, то сильно подбросит.
    func batYarn() {
        guard let k = nearestYarn() else { return }
        let dir: CGFloat = Bool.random() ? 1 : -1     // в какую сторону отскочит — случайно
        k.vx = dir * CGFloat.random(in: 3...14)       // сила удара каждый раз разная
        k.vy = CGFloat.random(in: 3...11)             // иногда подкидывает повыше
        k.landed = false
        playCool = 16                               // ~1.6 c не гнаться снова — мяч успевает отлететь
        boredom = max(0, boredom - 0.05)            // игра развлекает
        playSat = min(1, playSat + 0.04)            // от СВОЕЙ игры постепенно надоедает (скучает с одним мячом)
        if playSat >= 0.85 { playTired = true }
    }

    // есть ли по курсу бега низкое препятствие (курсор / клубок / лежащий корм), чтобы перепрыгнуть
    func obstacleAhead(_ dir: CGFloat) -> Bool {
        let lead: CGFloat = SIZE * 1.7
        func ahead(_ ox: CGFloat, _ oy: CGFloat) -> Bool {
            let d = ox - x
            return d * dir > 0 && abs(d) < lead && (oy - y) < SIZE     // впереди, близко и невысоко
        }
        let m = NSEvent.mouseLocation
        if ahead(m.x, m.y) { return true }
        for k in yarns where ahead(k.x, k.y) { return true }
        for c in kibbles where c.landed && ahead(c.x, bottomY()) { return true }
        return false
    }

    func stepPreamble() {
        y = bottomY()
        stTicks += 1
        let mm = NSEvent.mouseLocation                       // движение курсора за тик (для побудки мышкой)
        mouseDelta = hypot(mm.x - lastMouseX, mm.y - lastMouseY)
        lastMouseX = mm.x; lastMouseY = mm.y
        if playCool > 0 { playCool -= 1 }                    // пауза после удара по мячу
        hunger = min(1, hunger + HUNGER_RATE * (mood == .hungry ? 2 : 1))  // голод растёт медленно (~8 ч)
        playSat = max(0, playSat - 0.0006)   // интерес к клубку восстанавливается медленно (дольше отдыхает)
        if playSat <= 0.35 { playTired = false }   // отдохнул — снова можно играть (гистерезис)

        // потребности: энергия и скука дрейфуют по состоянию
        switch st {
        case .sleep:          energy = min(1, energy + 0.0008); boredom = min(1, boredom + 0.0004)
        case .walk:           energy = max(0, energy - 0.0005); boredom = max(0, boredom - 0.0020)  // спокойная ходьба почти не утомляет
        case .zoomies, .hunt: energy = max(0, energy - 0.0011); boredom = max(0, boredom - 0.0030)  // беготня/охота тратит силы
        case .digging, .away: boredom = max(0, boredom - 0.0015)   // прогулка тоже развлекает
        case .idle:           energy = min(1, energy + 0.0004); boredom = min(1, boredom + 0.0007)
        default: break
        }

        // корм привлекает голодного кота и ПРЕРЫВАЕТ почти всё (в т.ч. прогулку «за стену» и копание),
        // чтобы инфа о корме доходила сразу. Не трогаем только сон / уход за экран / падение / охоту-игру.
        if hunger > EAT_HUNGER && !eating, let c = foodTargetX() {
            switch st {
            case .walk:
                goingAway = false; leaving = false           // прервать уход на прогулку ради еды
                toFood = true; toPlay = false; targetX = c
            case .zoomies, .idle, .digging:
                goingAway = false; leaving = false
                toFood = true; toPlay = false; targetX = c; enter(.walk)
            default: break                                   // sleep/away/falling/hunt/play — не прерываем
            }
        }
    }

    func runState(decide: () -> Void) {
        var img: NSImage
        switch st {
        case .zoomies:
            let tx = targetX ?? x
            let dx = tx - x
            let west = dx < 0                              // направление бега
            // прыгает ТОЛЬКО чтобы перепрыгнуть препятствие по курсу (курсор / мяч / лежащий корм) — раньше и выше
            if zoomHop == 0, obstacleAhead(dx > 0 ? 1 : -1) { zoomHop = 15 }
            let pose: NSImage
            if zoomHop > 0 {
                let step = 15 - zoomHop                    // 0..14
                hopOffset = CGFloat(sin(Double(step) / 14.0 * .pi)) * 48   // повыше, чтобы уверенно перепрыгнуть
                pose = frame("jump", min(4, step / 3), flip: west)
                zoomHop -= 1
            } else {
                hopOffset = 0
                pose = frame(west ? "W" : "E", anim)
            }
            if abs(dx) <= ZOOM {
                x = tx
                zoomReps -= 1
                if zoomReps <= 0 {
                    if Double.random(in: 0..<1) < 0.22 { startWalkabout(); img = frame(west ? "W" : "E", anim) }  // добегался → иногда удирает за экран
                    else { enter(.idle); img = frame("idle", 0) }
                }
                else { targetX = (tx <= leftEdge() + 1) ? rightEdge() : leftEdge(); img = pose }
            } else {
                x += dx > 0 ? ZOOM : -ZOOM
                img = pose
            }
        case .walk:
            let rushing = toFood || toPlay                       // к еде/мячу — бежит во весь опор
            let sp: CGFloat = rushing ? FOOD_SPEED : SPEED
            let tx = targetX ?? x
            let dx = tx - x
            if abs(dx) <= sp {
                x = tx
                if leaving { leaving = false; win.orderOut(nil); enter(.away); img = frame("idle", 0) }
                else if goingAway { enter(.digging); img = frame(awayLeft ? "digL" : "digR", 0) }
                else if toPlay {
                    if let k = nearestYarn(), abs(k.y - y) < SIZE {   // мяч в пределах досягаемости по высоте
                        toPlay = false; batYarn(); enter(.play); img = frame("held", 0)
                    } else {                                          // мяч ещё летит сверху — ждём под ним, не бьём воздух
                        img = frame("alert", 0)
                    }
                }
                else { toFood = false; eatNearbyKibble(); enter(.idle); img = frame("idle", 0) }
            } else {
                x += dx > 0 ? sp : -sp
                img = frame(dx > 0 ? "E" : "W", anim / (rushing ? 3 : 5))   // спокойная ходьба — лапы медленнее, бег к цели — быстрее
            }
        case .digging:
            img = frame(awayLeft ? "digL" : "digR", stTicks / 5)   // копает дырку
            if stTicks > stDur {                    // прокопал → уходит за край шагами
                leaving = true; goingAway = false
                targetX = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                enter(.walk)
            }
        case .away:
            img = frame("idle", 0)                  // не виден
            if stTicks > stDur {                    // возвращается из-за края шагами
                goingAway = false; leaving = false
                x = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                y = bottomY()
                win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
                win.orderFrontRegardless()
                targetX = randomX(); toFood = false; enter(.walk)
            }
        case .idle:
            if eating {
                if let k = eatingRef, k.landed, !k.dragging, abs(k.x - x) <= SIZE / 2 {   // лежит рядом, не схвачен
                    img = frame("eat", 0)
                    biteTick += 1
                    if biteTick >= 16 {             // очередной укус
                        biteTick = 0
                        k.eaten += 1
                        hunger = max(0, hunger - SATIATION / Double(k.maxBites))  // сытость от каждого укуса
                        k.dot.stage = min(KibbleDot.stages.count - 1,
                                          Int(Double(k.eaten) / Double(k.maxBites) * Double(KibbleDot.stages.count)))
                        if k.eaten >= k.maxBites {  // доел этот катышек
                            k.win.orderOut(nil)
                            kibbles.removeAll { $0 === k }
                            eatingRef = nil; eating = false
                            if hunger > FULL, let c = foodTargetX() {   // ещё не наелся и есть корм — к следующему
                                toFood = true; targetX = c; enter(.walk)
                            } else {
                                decide()
                            }
                        }
                    }
                } else {                            // схватили/улетел — перестаём есть
                    eating = false; eatingRef = nil; img = frame("idle", 0)
                }
            } else {
                if stTicks > stDur / 4 && stTicks < stDur * 3 / 4 {
                    img = frame("scratch", stTicks / 4)     // умывается
                } else {
                    img = frame("idle", 0)
                }
                if stTicks > stDur { decide() }
            }
        case .sleep:
            img = frame("sleep", stTicks / 8)
            let m = NSEvent.mouseLocation
            let poke = abs(m.x - x) < SIZE && abs(m.y - y) < SIZE * 1.5 && mouseDelta > 3
            if poke {
                enter(.idle)                                // РАЗБУДИЛИ МЫШКОЙ (курсор движется рядом)
            } else if bedtimeNow {
                // ночью спит подолгу и по энергии НЕ просыпается; ОЧЕНЬ редко встанет ненадолго пройтись
                if stTicks > 600 && Double.random(in: 0..<1) < 0.0001 { targetX = randomX(); enter(.walk) }
            } else if energy >= 0.92 {
                decide()                                    // днём выспался — встал сам
            }
        case .hunt:
            if stTicks < 7 {                                // присел перед прыжком
                img = frame("alert", 0)
            } else if stTicks < 17 {                        // прыжок-дуга В СТОРОНУ мыши
                let p = CGFloat(stTicks - 7) / 10
                x = huntStartX + (huntAimX - huntStartX) * p                // летит к мыши по x
                hopOffset = huntHopH * CGFloat(sin(Double(p) * .pi / 2))    // вверх, пик в конце дуги
                img = frame("hang", 0)                      // поза как при висении (вытянутые лапы)
                let m = NSEvent.mouseLocation
                if abs(m.x - x) < 12 && (y + hopOffset + SIZE / 2) >= m.y - 6 {   // достал курсор (и по x, и по высоте)
                    clinging = true
                    clingPrevX = m.x; clingPivotV = 0; clingAngle = 0; clingVel = 0; clingTicks = 0
                    return                       // сразу висим — без кадра «на земле»
                }
            } else {                                        // не поймал — падает с верхней точки (без снапа), в позе висения
                huntCool = 12
                boredom = max(0, boredom - 0.15)            // охота развлекает
                fallY = y + hopOffset; fallVx = 0; fallVy = 0; flySpin = 0; flyHang = true
                hopOffset = 0
                st = .falling
                return
            }
        case .play:
            img = frame("held", anim / 3)                   // лапками по клубку — как при подвешивании
            if stTicks > stDur { enter(.idle) }
        case .falling:
            img = frame("held", 0)                          // (обрабатывается выше)
        }
        iv.image = img
        let drop: CGFloat = eating ? 6 : 0   // когда ест — садится ниже, чтоб попа не висела
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2 - drop + hopOffset))
        anim += 1
    }
}

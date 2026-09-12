extends StatComponent
class_name ManaComponent

signal spent(amount: float)

func can_afford(amount: float) -> bool:
	return current >= amount

func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if not can_afford(amount):
		return false
	var lost := _lose(amount)
	spent.emit(lost)
	return true

func drain(rate: float, delta: float) -> bool:
	return spend(rate * delta)

func restore(amount: float) -> float:
	return _gain(amount)

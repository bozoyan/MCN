# Scene Cast must contain all dialogue Characters

A Scene Cast is an explicit ordered superset of the Characters referenced by that Scene's dialogue elements: element writes preserve the existing Cast order and append missing speakers in order of first appearance, while a Cast write that omits a referenced Character fails with `dependent_elements_exist` and identifies the dependent elements. Rejecting the removal instead of allowing an inconsistent Cast or silently adding the Character back keeps the cast matrix truthful and makes write results match the caller's request.

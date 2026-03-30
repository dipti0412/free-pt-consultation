from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, computed_field


class WorkoutType(str, Enum):
    EXTERNAL = "External"
    INTERNAL = "Internal"


class WorkoutSource(str, Enum):
    GARMIN = "Garmin"
    MANUAL = "Manual"
    APPLE_HEALTH = "AppleHealth"


class Muscle(str, Enum):
    CHEST = "Chest"
    BACK = "Back"
    SHOULDERS = "Shoulders"
    BICEPS = "Biceps"
    TRICEPS = "Triceps"
    CORE = "Core"
    LEGS = "Legs"
    GLUTES = "Glutes"
    CALVES = "Calves"


class GoalType(str, Enum):
    STRENGTH = "Strength"
    RUNNING = "Running"
    CONSISTENCY = "Consistency"
    SKILL = "Skill"


class WorkoutBlockType(str, Enum):
    STRENGTH = "Strength"
    CARDIO = "Cardio"
    MOBILITY = "Mobility"


class SmallWinCategory(str, Enum):
    STRENGTH = "Strength"
    CARDIO = "Cardio"
    CONSISTENCY = "Consistency"
    HABIT = "Habit"


class Unit(str, Enum):
    LBS = "lbs"
    MILES = "miles"
    PACE = "pace"
    REPS = "reps"


class NutritionTrigger(str, Enum):
    POST_WORKOUT = "PostWorkout"


class WorkoutCategory(str, Enum):
    STRENGTH = "Strength"
    CARDIO = "Cardio"


class Exercise(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str
    primaryMuscles: list[Muscle]
    secondaryMuscles: list[Muscle]
    isUpperBody: bool
    progressionIncrementLbs: float


class WorkoutBlock(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    type: WorkoutBlockType
    exercises: list[Exercise]
    durationMinutes: float | None = None
    linkedWorkoutId: UUID | None = None


class Workout(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    startTime: datetime
    endTime: datetime
    type: WorkoutType
    source: WorkoutSource
    durationMinutes: float
    caloriesBurned: float
    distanceMiles: float | None = None
    pacePerMile: float | None = None
    workoutBlocks: list[WorkoutBlock]

    @computed_field(return_type=float | None)
    @property
    def pacePerKm(self) -> float | None:
        if self.pacePerMile is None:
            return None
        return round(self.pacePerMile / 1.60934, 4)


class SetEntry(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    reps: int
    weightLbs: float
    isCompleted: bool


class Goal(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    type: GoalType
    name: str
    currentValue: float
    targetValue: float
    unit: Unit
    lastUpdatedDate: date


class SmallWin(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    date: date
    lastUpdatedDate: date
    relatedWorkoutId: UUID | None = None
    message: str
    category: SmallWinCategory


class NutritionSuggestion(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    trigger: NutritionTrigger
    relatedWorkoutType: WorkoutCategory
    message: str
    checklistItems: list[str]
    completedItems: set[str]


class SourceRecord(BaseModel):
    source: str = Field(description="Source system identifier")
    captured_at: datetime
    payload: dict[str, object]

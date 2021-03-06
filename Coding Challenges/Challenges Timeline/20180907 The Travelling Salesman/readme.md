### The Travelling Salesman Problem

This weeks challenge contains

- A game server to submit your solutions and see your score in real time.
- No need for API keys.
- A simplified interface.
- No need to compute sha1 hashes.
- An interesting scoring mechanism. 

In other words, everything you've ever dreamt of.

## Introduction

We play in the cartesian plan, meaning the 2D space where each point has two coordinates. Such a pair of coordinates is written `(2, -2.17)`, for the point whose first coordinate is `2` and the second coordinate is `-2.17`.

The game server will generate 12 points. We will be referring to such a choice as a **map**.

Your mission, should you choose to accept it, is to solve the [travelling salesman problem](https://en.wikipedia.org/wiki/Travelling_salesman_problem) on that map.

## Game mechanics

Say hello to the server

```
curl http://10.249.16.173:14361
```

### Game API and datatypes

To get the current map:

```
curl http://10.249.16.173:14361/game/v1/map
```

This will return a JSON object looking like this

```
{
    "mapId"  : "796b1df1-b0e9-4138-ae2d-9aa681dd2ed6",
    "timestamp": "2018-09-07-11",
    "points" : [
        {
            "label" : "e167",
            "coordinates": [2, -2.17]
        }
        ...
    ]
}
```

The `timestamp` is the the date and the hour. The value `2018-09-07-11` says that the map lives until 11:59 on 2018-09-07.

Each point has a label and coordinates. The label is unique to that point and will be used by you to refer to the point later on. 

You will then want to submit a solution. A solution is an ordered sequence of points that the salesman should go through. From the first point to the last. All points must be visited.

Assuming that you think the salesman should visit the points in this order: `e167` -> `f432` -> ... -> `21dd`, you would then call

```
curl http://10.249.16.173:14361/game/v1/submit/<yourname>/<mapId>/e167,f432,...,21dd
```

After `submit`, you indicate your name, like, say, "pascal.honore". Try and use the same name during the entire duration of the game. Then you specify the `mapId`, this to ensure that you do not submit a solution for the wrong map. Then you list the points by giving their labels separated by comas.

When you submit a solution the server will compute the length of the path specified by your sequence. You should try and minimise that path, and again all the points should be in your path.

### Scoring

Here I need to introduce the scoring. There won't be one winner (and everybody else is a loser). We are going to use the same geometric scoring we used in the past. The best player gets the maximum number of points and the second player gets 70% of that etc...

### Scheduling

A new map is going to be generated each hour. Moreover you need to submit your best solution before the end of the hour because once a new map is generated you can't submit a solution for an old one. You can submit more than one solution for each map, and the server will just keep your best solution, so in doubt just submit.

### Scoring (again)

The points attribution mechanism is independent between maps. In other words, the points you got in the previous maps (aka in the previous hour) are permanently awarded and will go to the leaderboard. 

Since we generate a new map every hour, each map carries a maximum of 0.1 points. If you are the best player of each hour for an entire week in a row, then you will make `0.1 * 24 * 7 = 16.8` points. Which makes this the best rewarded challenge so far. 

### Versions

The API urls have a fragment `v1`. This is because we want this game to run more than one week (with updates between weeks). This is then the version of the challenge you are playing. The next version (either an update next week or simply an update mid-week will be at `v2` etc). Each version will have its own documented url scheme, but all against the same game server and all variations of the same problem. 

### Game score report

The game has got its own scoring which can bee seen at

```
curl http://10.249.16.173:14361/game/v1/scores
```

### Notes

- The lack of API key means that nothing prevents you from submitting a solution pretending being somebody else, meaning using somebody else's name. But since the server only keeps the best solution against each name, in the worse case you will do nothing, and in the best case you will have improved somebody else's solution. 
- As with the games I design, you can play manually using `curl`, but you probably want to write something to extract the current map, compute your best path and submit it. Don't forget to do it before the end of the hour!
- Calling a past map

	```
	http://10.249.16.173:14361/game/v1/map/2018-09-11-13
	```
- Visualizing a past map

	```
	http://10.249.16.173:14361/game/v1/map/2018-09-11-13/visualise
	```
	
	Also https://github.com/guardian/techtime/pull/14
---
title: "SIGRobotics at Cal Hacks 12.0 & Embodied AI Hackathon"
authors: 
  - "SIGRobotics"
---

Last weekend (Oct. 24-26), two SIGRobotics teams set off for San Francisco to compete in Cal Hacks 12.0 and the Embodied AI Hackathon.

## Embodied AI Hackathon

![Left to right: Stephen Zhu, Hasan Al Saeedi, Keshav Badrinath, Filip Kujuwa, Himank Handa, Sanjit Kumar, Aarsh Mittal, Leo Lin](SIGRobotics_Seeed_Team.jpg)

<br/>

Leo Lin, Himank Handa, Keshav Badrinath, Aarsh Mittal, Filip Kujawa, Sanjit Kumar, Stephen Zhu, and Hasan Al Saeedi from SIGRobotics placed first at the Embodied AI Hackathon hosted by NVIDIA, HuggingFace, and Seeed Studio. Their winning project featured a matcha-making robot, which they named *Performative*. Their project was a demonstration of embodied AI, a field that leverages novel generative AI methods to help robots learn how to perform real-world tasks.

The team engineered a setup with two SO-101 robotics arms to replicate the fine-grained motions part of the process of making matcha. They used NVIDIA’s most powerful robotics foundation model, GR00T N1.5, a VLA (vision language action model) which receives image and natural language prompts as input and outputs a corresponding action (similar to how you would chat with ChatGPT, but instead of returning a paragraph, your robot performs actions for you). The inference to run this model on the robot was executed on an NVIDIA Jetson.

Though there were many hardware challenges along the way, including one of the arms and one of the cameras completely breaking, the team adapted and overcame these, fine-tuning and running their final model for the first time 20 minutes before the demo to the judges (the second time they ran it was during the demo!). Read more about this project here: [here](https://www.hackster.io/sigrobotics/embodied-ai-hackathon-submission-sigrobotics-1st-place-f0e520)


## Cal Hacks 12.0

![Left to right: Yash Yardi, William Po-Yen Chou, Tanish Mittal, Krish Konda](SIGRobotics_CalHacks_Team.jpeg)

<br/>

Last weekend, four SIGRobotics members, Yash Yardi, William Po-Yen Chou, Tanish Mittal, and Krish Konda, took off for San Francisco to compete in the World’s Largest Collegiate Hackathon: Cal Hacks 12.0. The event brought together 2000+ competitors to the Palace of Fine Arts, with scenic views and a packed agenda for 36 hours of nonstop building, coding, and creative chaos. The team set out to build a robot that could draw what you imagined. 

They call it MARC: Marker Actuated Robotic Controller, which takes natural-language prompts and turns them into real pen-on-paper drawings. The system uses an LLM for image generation to create artwork from a user’s prompt and then converts it into precise motion commands. Then, an SO-100 robotic arm follows the commands to physically sketch the image. 

After demoing MARC at Cal Hacks, the team won second place in the robotics track! The hackathon put the team’s collaboration and design skills to the test, with Krish commenting, “This was a great experience, and developing MARC gave us inspiration to make this into something anyone can use.” See more about this project here: [here](https://devpost.com/software/marc-marker-actuated-robotic-controller)

import 'package:flutter/material.dart';

class TodoView extends StatefulWidget {
  const TodoView({super.key});

  @override
  State<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<TodoView> {
  Icon icon = Icon(Icons.radio_button_off_sharp, color: Colors.grey, size: 20);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: 20,
          itemBuilder: (context, index) {
            return Container(
              margin: EdgeInsets.fromLTRB(5, 5, 5, 0),
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 1,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),

              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      icon = Icon(Icons.task_alt, color: Colors.grey);
                      setState(() {});
                    },
                    // icon: icon,
                    icon: Icon(
                      Icons.radio_button_off_sharp,
                      color: Colors.blue,
                      size: 30,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("计算机证书考试", style: TextStyle(color: Colors.black)),
                      Row(
                        children: [
                          index == 0 || index == 2
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(50),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color.fromARGB(
                                          255,
                                          239,
                                          154,
                                          154,
                                        ),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.fromLTRB(5, 0, 5, 2),
                                  child: Text(
                                    "已逾期",
                                    style: TextStyle(fontSize: 10),
                                  ),
                                )
                              : Container(),
                          SizedBox(width: 5),

                          index == 1 || index == 2
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(50),
                                    boxShadow: [
                                      BoxShadow(color: Colors.amberAccent),
                                    ],
                                  ),
                                  padding: EdgeInsets.fromLTRB(5, 0, 5, 2),
                                  child: Text(
                                    "周期",
                                    style: TextStyle(fontSize: 10),
                                  ),
                                )
                              : Container(),
                          SizedBox(width: 5),
                          Text("7/12", style: TextStyle(color: Colors.black)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
